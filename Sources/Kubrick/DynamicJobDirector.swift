//
//  DynamicJobDirector.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "DynamicJobs")


public protocol DynamicJobDirector {

  func run<DynamicJob: Job>(job: DynamicJob) async throws -> DynamicJob.Value
  func run<DynamicJob: Job>(job: DynamicJob) async throws where DynamicJob.Value == NoValue

  func result<DynamicJob: Job>(for job: DynamicJob) async -> Result<DynamicJob.Value, Error>
  func result<DynamicJob: Job>(for job: DynamicJob) async -> Result<Void, Error> where DynamicJob.Value == NoValue

}


struct CurrentDynamicJobDirector: DynamicJobDirector {

  let director: JobDirector
  let parentJobKey: JobKey

  func run<DynamicJob: Job>(job: DynamicJob) async throws -> DynamicJob.Value {

    logger.jobTrace { $0.debug("[\(parentJobKey)] Running dynamic job: job-type=\(DynamicJob.self)") }

    return try await director.resolve(job, submission: parentJobKey.submission).result.get()
  }

  func run<DynamicJob: Job>(job: DynamicJob) async throws where DynamicJob.Value == NoValue {

    logger.jobTrace { $0.debug("[\(parentJobKey)] Running dynamic job: job-type=\(DynamicJob.self)") }

    _ = try await director.resolve(job, submission: parentJobKey.submission)
  }

  func result<DynamicJob: Job>(for job: DynamicJob) async -> Result<DynamicJob.Value, Error> {

    logger.jobTrace { $0.debug("[\(parentJobKey)] Running dynamic job: job-type=\(DynamicJob.self)") }

    let result: JobResult<DynamicJob.Value>
    do {
      result = try await director.resolve(job, submission: parentJobKey.submission).result
    }
    catch {
      result = .failure(error)
    }

    switch result {
    case .success(let value):
      return .success(value)
    case .failure(let error):
      return .failure(error)
    }
  }

  func result<DynamicJob: Job>(for job: DynamicJob) async -> Result<Void, Error> where DynamicJob.Value == NoValue {

    logger.jobTrace { $0.debug("[\(parentJobKey)] Running dynamic job: job-type=\(DynamicJob.self)") }

    let result: JobResult<DynamicJob.Value>
    do {
      result = try await director.resolve(job, submission: parentJobKey.submission).result
    }
    catch {
      result = .failure(error)
    }

    switch result {
    case .success:
      return .success(())
    case .failure(let error):
      return .failure(error)
    }
  }
}
