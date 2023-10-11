//
//  MapJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct MapJob<SourceJob: Job, NewValue: JobValue>: Job {

  public typealias Value = NewValue

  let source: (id: UUID, job: SourceJob)
  let transform: (SourceJob.Value) async throws -> NewValue

  public init(source: SourceJob, transform: @escaping (SourceJob.Value) async throws -> NewValue) {
    self.source = (UUID(), source)
    self.transform = transform
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    return [AdHocJobInputDescriptor(id: source.id, job: source.job)]
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {

    guard let inputResult = inputResults[source.id] else {
      return .failure(JobExecutionError.invariantViolation(.inputResultMissing))
    }
    
    switch inputResult {
    case .failure(let error):
      return .failure(error)

    case .success(let inputValue):
      guard let value = inputValue as? SourceJob.Value else {
        return .failure(JobExecutionError.invariantViolation(.inputResultInvalid))
      }
      do {
        return .success(try await transform(value))
      }
      catch {
        return .failure(error)
      }
    }
  }

}

public extension Job {

  func map<NewValue: JobValue>(_ transform: @escaping (Value) async throws -> NewValue) -> some Job<NewValue> {
    return MapJob(source: self, transform: transform)
  }

  func mapToResult() -> some Job<ExecuteResult<Value>> {
    return map { .success($0) }.catch { .failure($0) }
  }

}

public extension ExecutableJob  {

  func map<NewValue: JobValue>(_ transform: @escaping () async throws -> NewValue) -> some Job<NewValue> {
    return MapJob(source: self) { _ in try await transform() }
  }

}
