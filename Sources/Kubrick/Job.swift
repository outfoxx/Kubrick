//
//  Job.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "Job")


public protocol Job<Value> {
  
  associatedtype Value: JobValue

  var inputDescriptors: [any JobInputDescriptor] { get }

  func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value>

  func finished() async

}


public extension Job {

  var inputDescriptors: [any JobInputDescriptor] {
    let mirror = Mirror(reflecting: self)
    return mirror.children.compactMap { (_, property) in
      property as? any JobInputDescriptor
    }
  }

  func finished() async {}

}


internal extension Job {

  func finished(
    as jobKey: JobKey,
    for director: JobDirector
  ) async {

    logger.jobTrace { $0.trace("[\(jobKey)] Calling 'finished'") }

    await JobDirector.$currentJobDirector.withValue(director) {
      await JobDirector.$currentJobKey.withValue(jobKey) {
        await finished()
      }
    }
  }

}
