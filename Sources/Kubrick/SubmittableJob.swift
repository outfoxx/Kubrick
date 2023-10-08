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
import PotentCodables
import PotentCBOR


private let logger = Logger.for(category: "SubmittableJob")


public protocol SubmittableJob: Job, Codable where Value == NoValue {

  static var typeId: String { get }

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


extension SubmittableJob {

  init(from data: Data, using decoder: CBORDecoder) throws {
    self = try decoder.decode(Self.self, from: data)
  }

  func encode(using encoder: CBOREncoder) throws -> Data {
    return try encoder.encode(self)
  }

}


// MARK: Wrapper

struct SubmittableJobWrapper: Codable {

  var job: any SubmittableJob

}


extension SubmittableJobWrapper {

  enum CodingError: Error {
    case noSubmittableJobTypeResolver
  }

  enum CodingKeys: String, CodingKey {
    case type = "@type"
    case value
  }

  init(from decoder: Decoder) throws {
    guard let jobTypeResolver = decoder.userInfo[submittableJobTypeResolverKey] as? SubmittableJobTypeResolver else {
      throw CodingError.noSubmittableJobTypeResolver
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let jobType = try jobTypeResolver.resolve(jobTypeId: container.decode(String.self, forKey: .type))
    self.job = try jobType.init(from: KeyedNestedDecoder(key: .value, container: container, decoder: decoder))
  }

  func encode(to encoder: Encoder) throws {
    guard let jobTypeResolver = encoder.userInfo[submittableJobTypeResolverKey] as? SubmittableJobTypeResolver else {
      throw CodingError.noSubmittableJobTypeResolver
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(jobTypeResolver.typeId(of: type(of: job)), forKey: .type)
    try job.encode(to: KeyedNestedEncoder(key: .value, container: container, encoder: encoder))
  }

}
