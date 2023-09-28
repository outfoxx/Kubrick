//
//  CatchJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct CatchJob<SourceJob: Job>: Job {

  public typealias Value = SourceJob.Value

  let source: (id: UUID, job: SourceJob)
  let handler: (Error) async throws -> Value

  init(source: SourceJob, handler: @escaping (Error) async throws -> Value) {
    self.source = (UUID(), source)
    self.handler = handler
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    [CatchJobInputDescriptor(id: source.id, job: source.job, handler: handler)]
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {

    guard let inputResult = inputResults[source.id] else {
      return .failure(JobError.invariantViolation(.inputResultMissing))
    }

    switch inputResult {
    case .success(let success):
      
      guard let inputValue = success as? Value else {
        return .failure(JobError.invariantViolation(.inputResultInvalid))
      }

      return .success(inputValue)

    case .failure(let error):
      do {
        return .success(try await handler(error))
      }
      catch let handlerError {
        return .failure(handlerError)
      }
    }
  }

}

public extension Job {

  func `catch`(handler: @escaping (Error) async throws -> Value) -> some Job<Value> {
    CatchJob<Self>(source: self, handler: handler)
  }

}

public extension ExecutableJob {

  func `catch`(handler: @escaping (Error) async throws -> Void) -> some Job<NoValue> {
    CatchJob(source: self) {
      try await handler($0)
      return NoValue.instance
    }
  }

}


struct CatchJobInputDescriptor<SourceJob: Job>: JobInputDescriptor {

  var id: UUID
  var job: SourceJob
  let handler: (any Error) async throws -> SourceJob.Value

  var reportType: SourceJob.Value.Type { SourceJob.Value.self }

  func resolve(
    for director: JobDirector,
    submission: JobID
  ) async throws -> (id: UUID, result: JobInputResult<SourceJob.Value>) {

    let resolved = try await director.resolve(job, submission: submission)
    switch resolved.result {
    case .success(let value):
      return (id, .success(value))

    case .failure(let error):
      do {
        return (id, .success(try await handler(error)))
      }
      catch {
        return (id, .failure(error))
      }
    }
  }

}
