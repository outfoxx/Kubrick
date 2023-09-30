//
//  RetryJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "RetryJob")


public struct RetryJob<SourceJob: Job, ResultValue: JobValue>: Job where SourceJob.Value == ResultValue {

  public typealias Value = ResultValue

  let source: SourceJob
  let filter: (_ error: any Error, _ nextAttempt: Int) async -> Bool

  init(source: SourceJob, filter: @escaping (any Error, Int) async -> Bool) {
    self.source = source
    self.filter = filter
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    [RetryingJobInputDescriptor(job: source, filter: filter)]
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {
    guard let inputResult = inputResults.values.first else {
      return .failure(JobExecutionError.invariantViolation(.inputResultInvalid))
    }
    switch inputResult {
    case .success(let inputValue):
      guard let value = inputValue as? SourceJob.Value else {
        return .failure(JobExecutionError.invariantViolation(.inputResultInvalid))
      }
      return .success(value)

    case .failure(let error):
      return .failure(error)
    }
  }

}


public extension Job {

  func retry(filter: @escaping (_ error: any Error, _ nextAttempt: Int) async -> Bool) -> some Job<Value> {
    return RetryJob(source: self, filter: filter)
  }

  func retry(maxAttempts: Int) -> some Job<Value> {
    return RetryJob(source: self) { _, nextAttempt in nextAttempt <= maxAttempts }
  }

}


struct RetryingJobInputDescriptor<SourceJob: Job>: JobInputDescriptor {

  var job: SourceJob
  let filter: (_ error: any Error, _ attempt: Int) async -> Bool

  var reportType: SourceJob.Value.Type { SourceJob.Value.self }

  func resolve(
    for director: JobDirector,
    submission: JobID
  ) async throws -> (id: UUID, result: JobResult<SourceJob.Value>) {

    let id = UUID()
    var attempt: Int = 1

    while true {

      let resolved = try await director.resolve(job, submission: submission)
      switch resolved {
      case (_, .success(let success)):
        return (id, .success(success))

      case (let jobKey, .failure(let error)):

        attempt += 1

        if await !filter(error, attempt) {
          return (id, .failure(error))
        }

        logger.jobTrace { $0.warning("[\(jobKey)] Failed, retrying: attempt=\(attempt)") }

        try await director.unresolve(jobKey: jobKey)
      }

    }
  }

}
