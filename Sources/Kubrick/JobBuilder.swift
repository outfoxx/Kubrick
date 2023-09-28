//
//  JobBuilder.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


@resultBuilder
public struct JobBuilder<Result: JobValue> {

  public static func buildBlock<RJ: Job<Result>>(_ components: RJ) -> some Job<Result> {
    components
  }

  public static func buildBlock<RJ: Job<Result>>(_ components: RJ...) -> [some Job<Result>] {
    components
  }

  public static func buildArray<RJ: Job<Result>>(_ components: [[RJ]]) -> [some Job<Result>] {
    components.flatMap { $0 }
  }

  public static func buildArray<RJ: Job<Result>>(_ components: RJ) -> [some Job<Result>] {
    [components]
  }

  public static func buildEither<FJ: Job<Result>, SJ: Job<Result>>(first component: FJ) -> some Job<Result> {
    _ConditionalJob(first: component, second: nil as SJ?)
  }

  public static func buildEither<FJ: Job<Result>, SJ: Job<Result>>(second component: SJ) -> some Job<Result> {
    _ConditionalJob(first: nil as FJ?, second: component)
  }

}


public struct _ConditionalJob<FirstJob: Job, SecondJob: Job>: Job where FirstJob.Value == SecondJob.Value {

  public typealias Value = FirstJob.Value

  let first: (id: UUID, job: FirstJob)?
  let second: (id: UUID, job: SecondJob)?

  public init(first: FirstJob?, second: SecondJob?) {
    self.first = first.flatMap { (UUID(), $0) }
    self.second = second.flatMap { (UUID(), $0) }
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    if let first {
      return [AdHocJobInputDescriptor(id: first.id, job: first.job)]
    }
    else if let second {
      return [AdHocJobInputDescriptor(id: second.id, job: second.job)]
    }
    fatalError()
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value> {
    if let first {
      return try await first.job.execute(as: jobKey, with: inputResults, for: director)
    }
    else if let second {
      return try await second.job.execute(as: jobKey, with: inputResults, for: director)
    }
    fatalError()
  }
}
