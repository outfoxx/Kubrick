//
//  JobDirector.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import CryptoKit
import Foundation
import OSLog
import PotentCBOR


private let logger = Logger.for(category: "JobDirector")


public actor JobDirector: Identifiable {

  public typealias ID = JobDirectorID

  public enum State: String, CustomStringConvertible {
    case created
    case running
    case stopped

    public var description: String { rawValue }
  }

  struct ResultState<Value: JobValue>: Codable {
    var result: JobResult<Value>
  }

  typealias JobTaskFuture = Future<Void, Error>

  typealias ResolvedInput = (id: UUID, result: AnyJobInputResult, resultType: Any.Type)
  typealias ResolvedInputs = [ResolvedInput]

  @TaskLocal static var currentJobKey: JobKey?
  @TaskLocal static var currentJobDirector: JobDirector?
  @TaskLocal static var currentJobInputResults: JobInputResults?

  public nonisolated let id: ID
  public nonisolated let injected: JobInjectValues

  private var tasks: [UUID: JobTaskFuture] = [:]
  private let tasksCancellation = CancellationSource()
  private let resultState: RegisterCache<JobKey, Data>
  private let store: JobDirectorStore
  private let jobEncoder: any JobEncoder
  private let jobDecoder: any JobDecoder
  private var state: State

  public init(
    id: JobDirectorID = .generate(),
    directory: URL,
    typeResolver: SubmittableJobTypeResolver & JobErrorTypeResolver
  ) throws {
    try self.init(id: id, directory: directory, jobTypeResolver: typeResolver, errorTypeResolver: typeResolver)
  }

  public init(
    id: JobDirectorID = .generate(),
    directory: URL,
    jobTypeResolver: SubmittableJobTypeResolver,
    errorTypeResolver: JobErrorTypeResolver
  ) throws {

    let allErrorTypesResolver = MultiJobErrorTypeResolver(resolvers: [
      errorTypeResolver,
      packageErrorTypesResolver
    ])

    let cborEncoder = CBOREncoder()
    cborEncoder.deterministic = true
    cborEncoder.userInfo[JobErrorBox.typeResolverKey] = allErrorTypesResolver

    let cborDecoder = CBORDecoder()
    cborDecoder.userInfo[JobErrorBox.typeResolverKey] = allErrorTypesResolver

    let store = try JobDirectorStore(location: Self.storeLocation(id: id, directory: directory),
                                     jobTypeResolver: jobTypeResolver,
                                     jobEncoder: cborEncoder,
                                     jobDecoder: cborDecoder)

    self.init(
      id: id,
      store: store,
      errorTypeResolver: errorTypeResolver,
      jobEncoder: cborEncoder,
      jobDecoder: cborDecoder
    )
  }

  init(
    id: ID,
    store: JobDirectorStore,
    errorTypeResolver: JobErrorTypeResolver,
    jobEncoder: any JobEncoder,
    jobDecoder: any JobDecoder
  ) {
    self.id = id
    self.store = store
    self.injected = JobInjectValues()
    self.resultState = RegisterCache(store: store)
    self.jobEncoder = jobEncoder
    self.jobDecoder = jobDecoder
    self.state = .created
  }

  @discardableResult
  public func submit(_ job: some SubmittableJob, id: JobID = .init(), expiration: Date = .now) async -> Bool {
    do {

      return try await self.storeAndProcess(job, id: id, expiration: expiration)
      
    }
    catch {

      logger.error("[\(id)] Submission failed: error=\(error, privacy: .public)")

      return false
    }
  }

  @discardableResult
  public func start() async throws -> Int {

    state = .running

    do {

      let jobs = try await store.loadJobs()

      for (job, id, expiration) in jobs {

        self.process(job, submission: id, expiration: expiration)
      }

      return jobs.count

    }
    catch {

      logger.error("Start failed: error=\(error, privacy: .public)")

      state = .stopped

      throw error
    }
  }

  public func stop(completionWaitTimeout seconds: TimeInterval? = nil) async throws {

    state = .stopped

    tasksCancellation.cancel()

    try? await waitForCompletionOfCurrentJobs(timeout: seconds ?? 1_000_000)

    tasks.removeAll()
  }

  public func waitForCompletionOfCurrentJobs(timeout seconds: TimeInterval) async throws {
    await withThrowingTaskGroup(of: Void.self) { group in

      group.addTask {
        _ = await Future.allSettled(Array(self.tasks.values)).get()
      }

      group.addTask {
        try await Task.sleep(seconds: seconds)
        throw CancellationError()
      }

      do {
        for try await _ in group {
          group.cancelAll()
        }
      }
      catch {
        group.cancelAll()
      }
    }
  }

  public var submittedJobCount: Int {
    get async throws { try await store.jobCount }
  }

  public func encode(_ value: some Encodable) throws -> Data {
    return try jobEncoder.encode(value)
  }

  public func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    return try jobDecoder.decode(type, from: data)
  }

  func resolve<J: Job>(
    _ job: J,
    submission: JobID
  ) async throws -> (jobKey: JobKey, result: JobResult<J.Value>) {

    let (jobKey, inputResults) = try await prepare(job: job, submission: submission)

    do {

      logger.jobTrace { $0.debug("[\(jobKey)] Fingerprint: job-type=\(type(of: job))") }

      let result = try await persist(job: job, key: jobKey, inputResults: inputResults)

      logger.jobTrace { $0.trace("[\(jobKey)] Resolved, returning result") }

      return (jobKey, result)
    }
    catch {
      return (jobKey, .failure(error))
    }
  }

  func unresolve(jobKey: JobKey) async throws {
    try await resultState.deregister(for: jobKey)
  }

  func runAs(jobKey: JobKey, operation: () async throws -> Void) async rethrows {
    try await Self.$currentJobDirector.withValue(self) {
      try await Self.$currentJobKey.withValue(jobKey) {
        try await operation()
      }
    }
  }

  private func storeAndProcess(_ job: some SubmittableJob, id: JobID, expiration: Date) async throws -> Bool {

    guard state == .running else {

      logger.error("Job submitted in '\(self.state)' state")

      throw JobDirectorError.invalidDirectorState
    }

    guard try await store.saveJob(job, id: id, expiration: expiration) else {

      logger.jobTrace { $0.info("[\(id)] Skipping proccessing of duplicate job") }

      return false
    }

    self.process(job, submission: id, expiration: expiration)

    return true
  }

  private func process(_ job: some SubmittableJob, submission: JobID, expiration: Date) {
    jobTask { [self] in
      do {
        let (jobKey, result) = try await resolve(job, submission: submission)

        if case .failure(let error) = result {
          logger.error("[\(submission)] Job processing failed: error=\(error, privacy: .public)")
        }

        try? await Task.sleep(until: expiration)

        logger.jobTrace { $0.debug("[\(submission)] Removing completed job") }

        await removeJob(jobKey: jobKey)
      }
      catch is CancellationError {

        logger.jobTrace { $0.debug("[\(submission)] Removing cancelled job") }

        try? await store.removeJob(for: submission)
      }
      catch {

        logger.error("[\(submission)] Unexpected processing failure: error=\(error, privacy: .public)")
      }
    }
  }

  private func resolveInputs(job: some Job, submission: JobID) async throws -> ResolvedInputs {

    logger.jobTrace { $0.trace("Resolving inputs: job-type=\(type(of: job))") }

    let unbound = job.inputDescriptors.filter(\.isUnbound)
    if !unbound.isEmpty {
      throw JobExecutionError.unboundInputs(jobType: type(of: job), inputTypes: unbound.map { $0.reportType })
    }

    return try await withThrowingTaskGroup(of: ResolvedInput.self) { group in

      for (idx, inputDescriptor) in job.inputDescriptors.enumerated() {

        logger.jobTrace {
          $0.trace(
            """
            [\(submission)] Resolving input \(idx): \
            job-type=\(type(of: job)), \
            value-type=\(inputDescriptor.reportType)
            """
          )
        }

        group.addTask {
          try await resolve(inputDescriptor)
        }
      }

      var resolved: ResolvedInputs = []
      for try await result in group {

        if result.result.isFailure {

          logger.jobTrace {
            $0.trace(
              """
              [\(submission)] Input resolve failed: \
              job-type=\(type(of: job)), \
              value-type=\(result.resultType), \
              error=\(String(describing: result))
              """
            )
          }

          group.cancelAll()
        }

        resolved.append(result)
      }

      return resolved
    }

    @Sendable func resolve(_ inputDescriptor: some JobInputDescriptor) async throws -> ResolvedInput {

      let resolved = try await inputDescriptor.resolve(for: self, submission: submission)

      let result: AnyJobInputResult
      switch resolved.result {
      case .success(let value):
        result = .success(value)

      case .failure(let error):
        result = .failure(error)
      }

      return (resolved.id, result, inputDescriptor.reportType)
    }
  }

  private func fingerprint(job: some Job, resolved: ResolvedInputs, submission: JobID) throws -> JobKey {

    var inputHasher = SHA256()
    inputHasher.update(type: type(of: job))

    for (_, result, type) in resolved {
      inputHasher.update(type: type)
      switch result {
      case .success(let value):
        try inputHasher.update(value: value)
      case .failure(let error):
        try inputHasher.update(value: JobErrorBox(error))
      }
    }

    return JobKey(submission: submission, fingerprint: inputHasher.finalized())
  }

  private func prepare(job: some Job, submission: JobID) async throws -> (JobKey, JobInputResults) {

    let resolvedInputs = try await resolveInputs(job: job, submission: submission)

    let jobKey = try fingerprint(job: job, resolved: resolvedInputs, submission: submission)
    let values = Dictionary(uniqueKeysWithValues: resolvedInputs.map { ($0.id, $0.result) })

    return (jobKey, values)
  }

  private func persist<J: Job>(
    job: J,
    key jobKey: JobKey,
    inputResults: JobInputResults
  ) async throws -> JobResult<J.Value> {

    logger.jobTrace { $0.trace("[\(jobKey)] Registering state") }

    let serializedState = try await resultState.register(for: jobKey) {

      logger.jobTrace { $0.trace("[\(jobKey)] Initializing state") }

      let result = try await job.execute(as: jobKey, with: inputResults, for: self)

      logger.jobTrace { $0.trace("[\(jobKey)] Serializing state") }

      return try self.encode(ResultState(result: result))
    }

    return try self.decode(ResultState<J.Value>.self, from: serializedState).result
  }

  private func removeJob(jobKey: JobKey) async {
    do {
      async let deregister: Void? = try await resultState.deregister(for: jobKey)
      async let remove: Void? = try store.removeJob(for: jobKey.submission)

      try await deregister
      try await remove
    }
    catch {
      logger.error("[\(jobKey.submission)] Failed to remove job: error=\(error, privacy: .public)")
    }
  }

  private func jobTask(operation: @Sendable @escaping () async -> Void) {
    let id = UUID()
    tasks[id] = Task.tracked(cancellationSource: tasksCancellation, operation: operation) {
      await self.removeTask(for: id)
    }
  }

  private func removeTask(for id: UUID) {
    tasks.removeValue(forKey: id)
  }

  private static func storeLocation(id: ID, directory: URL) -> URL {
    return directory.appendingPathComponent(id.description).appendingPathExtension("job-store")
  }

}


// MARK: Errors


public enum JobDirectorError: JobError {

  case invalidDirectorState

}


private let packageErrorTypesResolver = TypeNameJobErrorTypeResolver(errors: [
  JobDirectorError.self,
  JobExecutionError.self,
  URLSessionJobManagerError.self,
  TypeNameSubmittableJobTypeResolver.Error.self,
  NSErrorCodingTransformer.Error.self
])


// MARK: Environment

extension JobEnvironment {
  public var dynamicJobs: DynamicJobDirector {
    get { CurrentDynamicJobDirector(director: currentJobDirector, parentJobKey: currentJobKey) }
  }
}

extension JobEnvironment {
  public var currentJobDirector: JobDirector {
    get {
      guard let director = JobDirector.currentJobDirector else {
        fatalError("No current job director. Jobs must be run by the JobDirector you cannot call execute directly")
      }
      return director
    }
  }
}

extension JobEnvironment {
  public var currentJobKey: JobKey {
    get {
      guard let key = JobDirector.currentJobKey else {
        fatalError("No current job key. Jobs must be run by the JobDirector you cannot call execute directly")
      }
      return key
    }
  }
}

extension JobEnvironment {
  public var currentJobInputResults: JobInputResults {
    get {
      guard let results = JobDirector.currentJobInputResults else {
        fatalError("No current job key. Jobs must be run by the JobDirector you cannot call execute directly")
      }
      return results
    }
  }
}
