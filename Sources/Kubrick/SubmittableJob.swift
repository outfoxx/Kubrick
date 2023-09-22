//
//  SubmittableJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog
import PotentCBOR


private let logger = Logger.for(category: "SubmittableJob")


public protocol SubmittableJob: Job where Value == NoValue {

  static var typeId: String { get }

  init(data: Data) throws

  func encode() throws -> Data

  func execute() async

}


public extension SubmittableJob {

  static var typeId: String { String(describing: Self.self) }

}


extension SubmittableJob {

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {

    logger.debug("[\(jobKey)] Executing")

    return await JobDirector.$currentJobDirector.withValue(director) {
      await JobDirector.$currentJobKey.withValue(jobKey) {
        await JobDirector.$currentJobInputResults.withValue(inputResults) {
          if let inputFailure = inputResults.failure {
            return .failure(inputFailure)
          }
          await execute()
          return .success(NoValue.instance)
        }
      }
    }
  }

}
