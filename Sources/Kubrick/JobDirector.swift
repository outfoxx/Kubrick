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

  public typealias ID = UniqueID

  public enum Error: Swift.Error {
    case unresolvedInputs
  }

  struct ResultState<Value: JobValue>: Codable {
    var result: JobResult<Value>
  }

  typealias ResolvedInput = (id: UUID, result: AnyJobResult, resultType: Any.Type, resultEncoded: Data)
  typealias ResolvedInputs = [ResolvedInput]

  @TaskLocal static var currentJobKey: JobKey?
  @TaskLocal static var currentJobDirector: JobDirector?
  @TaskLocal static var currentJobInputResults: JobInputResults?

  public nonisolated let id: ID
  public nonisolated let injected: JobInjectValues

  private let taskQueue = TaskQueue()
  private let resultState: RegisterCache<JobKey, Data>
  private let store: JobDirectorStore

  public init(
    id: ID = .generate(),
    directory: URL,
    typeResolver: SubmittableJobTypeResolver
  ) throws {
    let store = try JobDirectorStore(location: Self.storeLocation(id: id, directory: directory),
                                     typeResolver: typeResolver)
    self.init(id: id, store: store)
  }

  init(id: ID, store: JobDirectorStore) {
    self.id = id
    self.store = store
    self.injected = JobInjectValues()
    self.resultState = RegisterCache(store: store)
  }

  public nonisolated func submit(_ job: some SubmittableJob, id: JobID = .init(), expiration: Date = .now) {
    taskQueue.addTask {
      do {
        try await self.submit(job, id: id, expiration: expiration)
      }
      catch {
        logger.error("Submission failed: error=\(error, privacy: .public)")
      }
    }
  }

  public func reload() async throws -> Int {

    let jobs = try await store.loadJobs()

    for (job, id, expiration) in jobs {

      taskQueue.addTask {

        try await self.process(job, submission: id, expiration: expiration)
      }
    }

    return jobs.count
  }

  public func waitForCompletionOfCurrentJobs(seconds: TimeInterval) async throws {
    return try await taskQueue.wait(forNanoseconds: UInt64(seconds * 1_000_000_000))
  }

  public var submittedJobCount: Int {
    get async throws { try await store.jobCount }
  }

  func submit(_ job: some SubmittableJob, id: JobID = .init(), expiration: Date = .now) async throws {

    guard try await store.saveJob(job, id: id, expiration: expiration) else {

      logger.info("[\(id)] Skipping proccessing of duplicate job")

      return
    }

    try await process(job, submission: id, expiration: expiration)
  }

  func resolve<J: Job>(_ job: J, submission: JobID) async throws -> (jobKey: JobKey, result: JobResult<J.Value>) {

    let (jobKey, inputResults) = try await prepare(job: job, submission: submission)

    do {

      logger.debug("[\(jobKey)] Fingerprint: job-type=\(type(of: job))")

      let result = try await persist(job: job, key: jobKey, inputResults: inputResults)

      logger.trace("[\(jobKey)] Resolved, returning result")

      return (jobKey, result)
    }
    catch {
      return (jobKey, .failure(error))
    }
  }

  func unresolve(jobKey: JobKey) async throws {
    try await resultState.deregister(for: jobKey)
  }

  private func process<J: SubmittableJob>(_ job: J, submission: JobID, expiration: Date) async throws {

    let (jobKey, result) = try await resolve(job, submission: submission)

    try await Task.sleep(until: expiration)

    logger.debug("[\(submission)] Removing completed job")

    try await removeJob(jobKey: jobKey)

    if case .failure(let error) = result {
      logger.error("[\(submission)] Submission processing failed: error=\(error, privacy: .public)")
    }
  }

  private func resolveInputs(job: some Job, submission: JobID) async throws -> ResolvedInputs {
    logger.trace("Resolving inputs: job-type=\(type(of: job))")

    @Sendable func resolve(_ inputDescriptor: some JobInputDescriptor) async throws -> ResolvedInput {

      let resolved = try await inputDescriptor.resolve(for: self, submission: submission)

      let result: AnyJobResult
      switch resolved.result {
      case .success(let value):
        result = .success(value)

      case .failure(let error):
        result = .failure(error)
      }

      let data = try CBOREncoder.deterministic.encode(resolved.result)

      return (resolved.id, result, inputDescriptor.reportType, data)
    }

    return try await withThrowingTaskGroup(of: ResolvedInput.self) { group in

      for (idx, inputDescriptor) in job.inputDescriptors.enumerated() {
        logger.trace("Resolving binding \(idx): job-type=\(type(of: job)), value-type=\(inputDescriptor.reportType)")

        group.addTask {
          try await resolve(inputDescriptor)
        }
      }

      var resolved: ResolvedInputs = []
      for try await result in group {
        
        if result.result.isFailure {
          group.cancelAll()
        }

        resolved.append(result)
      }

      return resolved
    }
  }

  private func fingerprint(job: some Job, resolved: ResolvedInputs, submission: JobID) throws -> JobKey {

    var inputHasher = SHA256()
    inputHasher.update(type: type(of: job))

    for (_, _, type, data) in resolved {
      inputHasher.update(type: type)
      inputHasher.update(data: data)
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

    logger.trace("[\(jobKey)] Registering state")

    let serializedState = try await resultState.register(for: jobKey) {

      logger.trace("[\(jobKey)] Initializing state")

      let result = try await job.execute(as: jobKey, with: inputResults, for: self)

      logger.trace("[\(jobKey)] Serializing state")

      return try CBOREncoder.deterministic.encode(ResultState(result: result))
    }

    return try CBORDecoder.default.decode(ResultState<J.Value>.self, from: serializedState).result
  }

  private func removeJob(jobKey: JobKey) async throws {
    
    async let deregister: Void? = try await resultState.deregister(for: jobKey)
    async let remove: Void? = try store.removeJob(for: jobKey.submission)

    try await deregister
    try await remove
  }

  private static func storeLocation(id: ID, directory: URL) -> URL {
    return directory.appendingPathComponent(id.description).appendingPathExtension("job-store")
  }

}


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
