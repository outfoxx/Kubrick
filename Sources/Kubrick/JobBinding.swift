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


public struct JobBinding<Value: JobValue> {

  typealias SourceJob = Job<Value>

  enum State {
    case job(UUID, any SourceJob)
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

  public var value: Value {
    get {
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
  }

  public mutating func set(value: Value) {
    state = .constant(UUID(), value)
  }

  public mutating func bind<SourceJob: Job<Value>>(job: SourceJob) {
    state = .job(UUID(), job)
  }

  public mutating func bind<SourceJob: Job<Value>>(@JobBuilder<Value> builder: () -> SourceJob) {
    bind(job: builder())
  }

}


internal extension JobBinding {

  var sourceJob: (any SourceJob)? {
    switch state {
    case .job(_, let job):
      return job

    default:
      return nil
    }
  }

  func resolve(for director: JobDirector, submission: JobID) async throws -> (UUID, JobResult<Value>) {

    @Sendable func resolve(_ job: some Job<Value>) async throws -> JobResult<Value> {
      try await director.resolve(job, submission: submission).result
    }

    switch state {
    case .job(let id, let job):
      return (id, try await resolve(job))

    case .constant(let id, let value):
      return (id, .success(value))

    case .unbound:
      fatalError("Job executing with unbound input")
    }
  }

}
