//
//  ExecutableJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "ExecutableJob")


public protocol ExecutableJob: Job where Value == NoValue {

  func execute() async throws

}


extension ExecutableJob {

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {

    logger.jobTrace { $0.trace("[\(jobKey)] Executing") }

    return await JobDirector.$currentJobDirector.withValue(director) {
      await JobDirector.$currentJobKey.withValue(jobKey) {
        await JobDirector.$currentJobInputResults.withValue(inputResults) {
          if let inputFailure = inputResults.failure {
            return .failure(inputFailure)
          }
          do {
            try await execute()
            return .success(NoValue.instance)
          }
          catch {
            logger.jobTrace { $0.error("[\(jobKey)] Execute failed: error=\(error)") }
            return .failure(error)
          }
        }
      }
    }
  }

}
