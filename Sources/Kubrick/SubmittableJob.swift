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


private let logger = Logger.for(category: "SubmittableJob")


public protocol SubmittableJob: Job where Value == NoValue {

  static var typeId: String { get }

  init(from data: Data, using decoder: any JobDecoder) throws

  func encode(using encoder: any JobEncoder) throws -> Data

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

    logger.jobTrace { $0.debug("[\(jobKey)] Executing") }

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


public extension SubmittableJob where Self: Codable {

  init(from data: Data, using decoder: any JobDecoder) throws {
    self = try decoder.decode(Self.self, from: data)
  }

  func encode(using encoder: any JobEncoder) throws -> Data {
    return try encoder.encode(self)
  }

}
