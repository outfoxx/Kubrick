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

  public static func buildExpression<RJ: Job<Result>>(_ expression: RJ) -> some Job<Result> {
    expression
  }

  public static func buildExpression<RJ: Job<Result>>(_ expression: RJ?) -> (some Job<Result>)? {
    expression
  }

  public static func buildExpression<Wrapped: JobValue, RJ: Job<Wrapped>>(_ expression: RJ) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalJob(source: expression)
  }

  public static func buildExpression<Wrapped: JobValue, RJ: Job<Wrapped>>(_ expression: RJ?) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalJob(source: expression)
  }

  public static func buildExpression<Wrapped: JobValue, RJ: Job<Result>>(_ expression: RJ) -> some Job<Result>
  where Result == Optional<Wrapped> {
    expression
  }

  public static func buildExpression<Wrapped: JobValue, RJ: Job<Result>>(_ expression: RJ?) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalOptionalJob<Wrapped, RJ>(source: expression)
  }

  public static func buildExpression(_ expression: Never) -> some Job<Result> {
    _NeverJob()
  }

  public static func buildBlock<RJ: Job<Result>>(_ components: RJ) -> some Job<Result> {
    components
  }

  public static func buildOptional<Wrapped: JobValue, RJ: Job<Result>>(_ component: RJ?) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalOptionalJob(source: component)
  }

  public static func buildEither<FJ: Job<Result>, SJ: Job<Result>>(first component: FJ) -> _ConditionalJob<Result, FJ, SJ> {
    _ConditionalJob(first: component, second: nil as SJ?)
  }

  public static func buildEither<FJ: Job<Result>, SJ: Job<Result>>(second component: SJ) -> _ConditionalJob<Result, FJ, SJ> {
    _ConditionalJob(first: nil as FJ?, second: component)
  }

  #if OPTIMIZE_BUILT_JOBS_IN_FINAL_RESULT

  public static func buildFinalResult<RJ: Job<Result>>(_ component: RJ) -> some Job<Result> {
    component
  }

  public static func buildFinalResult<Wrapped: JobValue, RJ: Job<Wrapped>>(
    _ component: _OptionalOptionalJob<Wrapped, _OptionalJob<Wrapped, RJ>>
  ) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalJob(source: component.source?.source)
  }

  public static func buildFinalResult<Wrapped: JobValue, RJ: Job<Result>>(
    _ component: _OptionalOptionalJob<Wrapped, _OptionalOptionalJob<Wrapped, RJ>>
  ) -> some Job<Result>
  where Result == Optional<Wrapped> {
    _OptionalOptionalJob(source: component.source?.source)
  }

  public static func buildFinalResult<RJ: Job<Result>>(_ component: _ConditionalJob<Result, RJ, RJ>) -> RJ {
    guard let job = (component.first ?? component.second) else {
      fatalError()
    }
    return job
  }

  #endif

}


public struct _NilJob<Wrapped: JobValue>: Job  {

  public typealias Value = Optional<Wrapped>

  public var inputDescriptors: [any JobInputDescriptor] { [] }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value> {
    return .success(nil)
  }
}

public struct _AnyJob<Value: JobValue>: Job {

  let source: any Job<Value>

  init(source: any Job<Value>) {
    self.source = source
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    return source.inputDescriptors
  }

  public func execute(as jobKey: JobKey, with inputResults: JobInputResults, for director: JobDirector) async throws -> JobResult<Value> {
    return try await source.execute(as: jobKey, with: inputResults, for: director)
  }

}

public struct _NeverJob<Value: JobValue>: Job {
  public func execute(as jobKey: JobKey, with inputResults: JobInputResults, for director: JobDirector) async throws -> JobResult<Value> {
    fatalError()
  }
}


public struct _ConditionalJob<Value, FirstJob: Job, SecondJob: Job>: Job where FirstJob.Value == Value, SecondJob.Value == Value {

  let first: FirstJob?
  let second: SecondJob?

  public init(first: FirstJob?, second: SecondJob?) {
    self.first = first
    self.second = second
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    if let first {
      return first.inputDescriptors
    }
    else if let second {
      return second.inputDescriptors
    }
    fatalError()
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value> {
    if let first {
      return try await first.execute(as: jobKey, with: inputResults, for: director)
    }
    else if let second {
      return try await second.execute(as: jobKey, with: inputResults, for: director)
    }
    fatalError()
  }
}


public struct _OptionalJob<Wrapped: JobValue, SourceJob: Job>: Job where SourceJob.Value == Wrapped  {

  public typealias Value = Optional<Wrapped>

  let source: SourceJob?

  init(source: SourceJob?) {
    self.source = source
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    guard let source else {
      return []
    }
    return source.inputDescriptors
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value> {

    guard let source else {
      return .success(nil)
    }

    return try await source.execute(as: jobKey, with: inputResults, for: director).wrapped
  }

}


public struct _OptionalOptionalJob<Wrapped: JobValue, SourceJob: Job>: Job where SourceJob.Value == Optional<Wrapped> {

  public typealias Value = Optional<Wrapped>

  let source: SourceJob?

  init(source: SourceJob?) {
    self.source = source
  }

  public var inputDescriptors: [any JobInputDescriptor] {
    guard let source else {
      return []
    }
    return source.inputDescriptors
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value> {

    guard let source else {
      return .success(nil)
    }

    return try await source.execute(as: jobKey, with: inputResults, for: director)
  }

}
