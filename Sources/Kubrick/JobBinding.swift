//
//  JobBinding.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "JobBinding")

public struct JobBinding<Value: JobHashable> {

  enum State {
    case job(UUID, any JobResolver<Value>)
    case constant(UUID, Value)
    case unbound
  }

  private var state: State

  public init() {
    self.state = .unbound
  }

  public init(_ value: Value) {
    self.state = .constant(UUID(), value)
  }

  public mutating func set(value: Value) {
    state = .constant(UUID(), value)
  }

  public mutating func bind<SourceJob: Job<Value>>(job: SourceJob) {
    state = .job(UUID(), PassthroughJobResolver(job: job))
  }

  public mutating func bind<WrappedValue: JobValue, SourceJob: Job<WrappedValue>>(job: SourceJob) where Value == Optional<WrappedValue> {
    state = .job(UUID(), OptionalJobResolver(job: job))
  }

  public mutating func bind<WrappedValue: JobValue, SourceJob: Job<Optional<WrappedValue>>>(job: SourceJob?) where Value == Optional<WrappedValue> {
    if let job {
      state = .job(UUID(), PassthroughJobResolver(job: job))
    }
    else {
      state = .constant(UUID(), nil)
    }
  }

  public mutating func bind<SourceJob: Job<Value>>(@JobBuilder<Value> builder: () throws -> SourceJob) rethrows {
    bind(job: try builder())
  }

  public mutating func bind<WrappedValue: JobValue, SourceJob: Job<WrappedValue>>(@JobBuilder<WrappedValue> builder: () throws -> SourceJob) rethrows where Value == Optional<WrappedValue> {
    bind(job: try builder())
  }

  var value: Value {
    switch state {
    case .constant(_, let value):
      return value

    case .job(let id, _):
      guard let results = JobDirector.currentJobInputResults else {
        fatalError("No input values, executing outside of resolve")
      }
      guard let result = results[id] else {
        fatalError("Resolved input not found")
      }
      guard case .success(let value) = result else {
        fatalError("Resolved input has failure")
      }
      guard let value = value as? Value else {
        fatalError("Resolved input has incorrect type")
      }
      return value

    case.unbound:
      fatalError("Unbound job input")
    }
  }

  var isUnbound: Bool {
    guard case .unbound = state else {
      return false
    }
    return true
  }

}


protocol JobResolver<Value> {
  associatedtype Value: JobHashable

  func resolve(for director: JobDirector, submission: JobID) async throws -> JobInputResult<Value>
}


struct PassthroughJobResolver<Value: JobValue>: JobResolver {

  let job: any Job<Value>

  func resolve(for director: JobDirector, submission: JobID) async throws -> JobInputResult<Value> {

    @Sendable func unboxedResolve(_ job: some Job<Value>) async throws -> JobResult<Value> {
      try await director.resolve(job, submission: submission).result
    }

    return try await unboxedResolve(job)
  }
}


struct OptionalJobResolver<Wrapped: JobValue>: JobResolver {

  typealias Value = Optional<Wrapped>

  let job: any Job<Wrapped>

  func resolve(for director: JobDirector, submission: JobID) async throws -> JobInputResult<Value> {

    @Sendable func unboxedResolve(_ job: some Job<Wrapped>) async throws -> JobResult<Value> {
      let result = try await director.resolve(job, submission: submission).result
      switch result {
      case .success(let value):
        return .success(value)
      case .failure(let error):
        return .failure(error)
      }
    }

    return try await unboxedResolve(job)
  }
}


internal extension JobBinding {

  func resolve(for director: JobDirector, submission: JobID) async throws -> (UUID, JobInputResult<Value>) {

    switch state {
    case .job(let id, let resolver):
      return (id, try await resolver.resolve(for: director, submission: submission))

    case .constant(let id, let value):
      return (id, .success(value))

    case .unbound:
      fatalError("Job executing with unbound input")
    }
  }

}
