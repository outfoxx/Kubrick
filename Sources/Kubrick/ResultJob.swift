//
//  ResultJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "ResultJob")


public protocol ResultJob<ResultValue>: Job where Value == ResultValue {

  associatedtype ResultValue

  func execute() async throws -> ResultValue

}


extension ResultJob {

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {

    logger.jobTrace { $0.debug("[\(jobKey)] Executing") }

    return await JobDirector.$currentJobDirector.withValue(director) {
      await JobDirector.$currentJobKey.withValue(jobKey) {
        await JobDirector.$currentJobInputResults.withValue(inputResults) {

          if let inputFailure = inputResults.failure {
            return .failure(inputFailure)
          }
          do {
            return .success(try await execute())
          }
          catch let error as JobTransferError {
            return .failure(error)
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
