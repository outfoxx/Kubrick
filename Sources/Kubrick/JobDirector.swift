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


/// Directs execution of submitted jobs.
/// 
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
  public nonisolated let mode: JobDirectorMode
  public nonisolated let injected: JobInjectValues

  internal let store: JobDirectorStore

  private let assistantsWatcher: AssistantsWatcher
  private let resultState: RegisterCache<JobKey, Data>
  private let jobEncoder: CBOREncoder
  private let jobDecoder: CBORDecoder
  private let tasksCancellation = CancellationSource()
  private var tasks: [UUID: JobTaskFuture] = [:]
  private var state: State

  public init(
    id: JobDirectorID = .generate(),
    directory: URL,
    mode: JobDirectorMode = .principal,
    typeResolver: SubmittableJobTypeResolver & JobErrorTypeResolver
  ) throws {
    try self.init(
      id: id,
      directory: directory,
      mode: mode,
      jobTypeResolver: typeResolver,
      errorTypeResolver: typeResolver
    )
  }

  public init(
    id: JobDirectorID,
    directory: URL,
    mode: JobDirectorMode,
    jobTypeResolver: SubmittableJobTypeResolver,
    errorTypeResolver: JobErrorTypeResolver
  ) throws {

    let allErrorTypesResolver = MultiJobErrorTypeResolver(resolvers: [
      errorTypeResolver,
      packageErrorTypesResolver
    ])

    let cborEncoder = CBOREncoder()
    cborEncoder.deterministic = true
    cborEncoder.userInfo[submittableJobTypeResolverKey] = jobTypeResolver
    cborEncoder.userInfo[jobErrorTypeResolverKey] = allErrorTypesResolver

    let cborDecoder = CBORDecoder()
    cborDecoder.userInfo[submittableJobTypeResolverKey] = jobTypeResolver
    cborDecoder.userInfo[jobErrorTypeResolverKey] = allErrorTypesResolver

    let store = try JobDirectorStore(location: Self.storeLocation(id: id, in: directory, mode: mode),
                                     jobTypeResolver: jobTypeResolver)

    let assistantsWatcher =
      try AssistantsWatcher(assistantsLocation: try Self.assistantsLocation(id: id, in: directory))

    self.init(
      id: id,
      mode: mode,
      store: store,
      assistantsWatcher: assistantsWatcher,
      errorTypeResolver: errorTypeResolver,
      jobEncoder: cborEncoder,
      jobDecoder: cborDecoder
    )
  }

  init(
    id: ID,
    mode: JobDirectorMode,
    store: JobDirectorStore,
    assistantsWatcher: AssistantsWatcher,
    errorTypeResolver: JobErrorTypeResolver,
    jobEncoder: CBOREncoder,
    jobDecoder: CBORDecoder
  ) {
    self.id = id
    self.mode = mode
    self.store = store
    self.assistantsWatcher = assistantsWatcher
    self.injected = JobInjectValues()
    self.resultState = RegisterCache(store: store)
    self.jobEncoder = jobEncoder
    self.jobDecoder = jobDecoder
    self.state = .created
  }

  @discardableResult
  public func submit(
    _ job: some SubmittableJob,
    as jobID: JobID = .init(),
    deduplicationWindow: TimeDuration = .zero
  ) async throws -> Bool {
    try await process(submitted: job, as: jobID, deduplicationExpiration: deduplicationWindow.dateAfterNow)
  }

  public func start() async throws {
    do {

      if mode.isPrincipal {

        // Load and start jobs currently in store

        let jobs = try await store.loadJobs()

        for (job, jobID, deduplicationExpiration) in jobs {

          self.process(saved: job, as: jobID, deduplicationExpiration: deduplicationExpiration)
        }

        // Start watcher transferring any orphaned jobs

        try await assistantsWatcher.start { jobURL in
          self.transferJob(from: jobURL)
        }

      }

      state = .running

    }
    catch {

      logger.error("Start failed: error=\(error, privacy: .public)")

      state = .stopped

      throw error
    }
  }

  public func stop(completionWaitTimeout seconds: TimeInterval? = nil) async throws {

    state = .stopped

    assistantsWatcher.stop()

    tasksCancellation.cancel()

    try? await waitForCompletionOfCurrentJobs(timeout: seconds ?? 1_000_000)

    await injected.stop()

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

  public nonisolated func transferToPrincipal() throws {
    guard let jobID = Self.currentJobKey?.id else {
      fatalError("\(#function) must be called from Job.execute")
    }

    guard mode.isAssistant else {
      return
    }

    logger.info("Transferring job to principal director: job-id=\(jobID)")

    throw JobTransferError.transferToPrincipalDirector
  }

  func resolve<J: Job>(
    _ job: J,
    as jobID: JobID,
    tags: [String]
  ) async throws -> (jobKey: JobKey, result: JobResult<J.Value>) {

    let (jobKey, inputResults) = try await prepare(job: job, as: jobID, tags: tags)

    do {

      logger.jobTrace { $0.debug("[\(jobKey)] Fingerprint: job-type=\(type(of: job))") }

      let result = try await persist(job: job, key: jobKey, inputResults: inputResults)

      logger.jobTrace { $0.trace("[\(jobKey)] Resolved, returning result") }

      return (jobKey, result)
    }
    catch let error as JobTransferError {

      return (jobKey, .failure(error))
    }
    catch {
      
      logger.jobTrace { $0.trace("[\(jobKey)] Resolve failed: error=\(error, privacy: .public)") }

      return (jobKey, .failure(error))
    }
  }

  func runAs(jobKey: JobKey, operation: () async throws -> Void) async rethrows {
    try await Self.$currentJobDirector.withValue(self) {
      try await Self.$currentJobKey.withValue(jobKey) {
        try await operation()
      }
    }
  }

  private func transferJob(from assistantJobURL: URL) {
    do {

      guard let jobID = JobID(string: assistantJobURL.deletingPathExtension().lastPathComponent) else {
        logger.error("Transferred job has invalid name: url=\(assistantJobURL, privacy: .public)")
        return
      }

      logger.info("Transferring job from assistant: job-id=\(jobID)")

      let jobURL = store.url(for: .jobPackage(id: jobID))
      try FileManager.default.moveItem(at: assistantJobURL, to: jobURL)

      Task {

        let loaded: JobDirectorStore.SubmittedJob
        do {
          loaded = try await store.loadJob(jobID: jobID)
        }
        catch {
          logger.info("Failed to load transferred job: job-id=\(jobID)")
          return
        }

        process(saved: loaded.job, as: loaded.id, deduplicationExpiration: loaded.deduplicationExpiration)
      }
    }
    catch {
      logger.error("Job transfer failed: error=\(error, privacy: .public)")
    }
  }

  private func process(
    submitted job: some SubmittableJob,
    as jobID: JobID,
    deduplicationExpiration: Date
  ) async throws -> Bool {

    guard state == .running else {

      logger.error("Job submitted in '\(self.state)' state")

      throw JobDirectorError.invalidDirectorState
    }

    guard try await store.saveJob(job, as: jobID, deduplicationExpiration: deduplicationExpiration) else {

      logger.jobTrace { $0.info("[\(jobID)] Skipping proccessing of duplicate job") }

      return false
    }

    self.process(saved: job, as: jobID, deduplicationExpiration: deduplicationExpiration)

    return true
  }

  private func process(saved job: some SubmittableJob, as jobID: JobID, deduplicationExpiration: Date) {
    jobTask { [self] in
      do {
        let jobHandle = try FileHandle(forDirectory: store.url(for: .jobPackage(id: jobID)))
        try jobHandle.lock()
        defer { try? jobHandle.unlock() }

        do {
          let (jobKey, result) = try await resolve(job, as: jobID, tags: [])

          if result.isTransfer {
            return
          }

          if case .failure(let error) = result {
            logger.error("[\(jobID)] Job processing failed: error=\(error, privacy: .public)")
          }

          // Sleep until it's time to remove job from storage
          try? await Task.sleep(until: deduplicationExpiration)

          logger.jobTrace { $0.debug("[\(jobID)] Removing completed job") }

          await removeJob(jobKey: jobKey)
        }
        catch is CancellationError {

          logger.jobTrace { $0.debug("[\(jobID)] Removing cancelled job") }

          try? await store.removeJob(for: jobID)
        }
        catch {
          logger.error("[\(jobID)] Unexpected processing failure: error=\(error, privacy: .public)")
        }
      }
      catch {
        logger.error("[\(jobID)] Failed to lock job: error=\(error, privacy: .public)")
      }
    }
  }

  private func resolveInputs(job: some Job, as jobID: JobID, tags: [String]) async throws -> ResolvedInputs {

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
            [\(jobID)] Resolving input \(idx): \
            job-type=\(type(of: job)), \
            value-type=\(inputDescriptor.reportType)
            """
          )
        }

        group.addTask {
          try await resolveInput(inputDescriptor)
        }
      }

      var resolvedInputs: ResolvedInputs = []
      for try await resolvedInput in group {

        if resolvedInput.result.isFailure && !resolvedInput.result.isTransfer {

          logger.jobTrace {
            $0.trace(
              """
              [\(jobID)] Input resolve failed: \
              job-type=\(type(of: job)), \
              value-type=\(resolvedInput.resultType), \
              error=\(String(describing: resolvedInput))
              """
            )
          }

          group.cancelAll()
        }

        resolvedInputs.append(resolvedInput)
      }

      return resolvedInputs
    }

    @Sendable func resolveInput(_ inputDescriptor: some JobInputDescriptor) async throws -> ResolvedInput {

      let resolved = try await inputDescriptor.resolve(for: self, as: jobID, tags: tags)

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

  private func fingerprint(
    job: some Job,
    resolved: ResolvedInputs,
    as jobID: JobID,
    tags: [String]
  ) throws -> JobKey {

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

    try inputHasher.update(value: tags)

    return JobKey(id: jobID, fingerprint: inputHasher.finalized(), tags: tags)
  }

  private func prepare(job: some Job, as jobID: JobID, tags: [String]) async throws -> (JobKey, JobInputResults) {

    let resolvedInputs = try await resolveInputs(job: job, as: jobID, tags: tags)

    let jobKey = try fingerprint(job: job, resolved: resolvedInputs, as: jobID, tags: tags)
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

      if result.isTransfer {
        throw JobTransferError.transferToPrincipalDirector
      }

      logger.jobTrace { $0.trace("[\(jobKey)] Serializing state") }

      return try self.encode(ResultState(result: result))
    }

    return try self.decode(ResultState<J.Value>.self, from: serializedState).result
  }

  private func removeJob(jobKey: JobKey) async {
    do {
      async let deregister: Void? = try await resultState.deregister(for: jobKey)
      async let remove: Void? = try store.removeJob(for: jobKey.id)

      try await deregister
      try await remove
    }
    catch {
      logger.error("[\(jobKey.id)] Failed to remove job: error=\(error, privacy: .public)")
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

  static func storeLocation(id: ID, in directory: URL, mode: JobDirectorMode) throws -> URL {
    let principalLocation = directory.appendingPathComponent(id.description).appendingPathExtension("job-store")
    switch mode {
    case .principal:
      try FileManager.default.createDirectory(at: principalLocation, withIntermediateDirectories: true)
      return principalLocation
    case .assistant(let assistantName):
      return try assistantsLocation(id: id, in: directory).appendingPathComponent(assistantName)
    }
  }

  static func assistantsLocation(id: ID, in directory: URL) throws -> URL {
    let url = try storeLocation(id: id, in: directory, mode: .principal).appendingPathComponent("assistants")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

}


// MARK: Errors


public enum JobDirectorError: JobError {

  case invalidDirectorState
  case unableToCreateJobsDirectory

}


private let packageErrorTypesResolver = TypeNameJobErrorTypeResolver(errors: [
  JobDirectorError.self,
  JobExecutionError.self,
  JobTransferError.self,
  URLSessionJobManagerError.self,
  TypeNameSubmittableJobTypeResolver.Error.self,
  NSErrorCodingTransformer.Error.self,
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
