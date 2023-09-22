//
//  DirectorTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@testable import Kubrick
import XCTest


class DirectorTests: XCTestCase {

  func test_Deduplication() async throws {

    struct MainJob: SubmittableJob {

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: () -> Void

      init(onExecute: @escaping () -> Void) {
        self.onExecute = onExecute
      }

      func execute() async {
        onExecute()
      }

      init(data: Data) throws {
        onExecute = {}
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)

    let executed = expectation(description: "MainJob executed")
    executed.expectedFulfillmentCount = 2
    executed.assertForOverFulfill = false

    let mainJob = MainJob {
      print("🎉 Executed!")
      executed.fulfill()
    }

    let jobID = JobID(string: "7UDE7RgDFjRbZYqVpowU1m")!

    func submit() async throws {

      func go() {
        director.submit(mainJob, id: jobID, expiration: .now.addingTimeInterval(0.5))
      }

      go()

      try await Task.sleep(for: .seconds(0.1))
    }

    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()

    try await director.taskQueue.wait()

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_LongDeduplication() async throws {

    struct MainJob: SubmittableJob {
      init() {}
      func execute() async { print("🎉 Executing") }
      init(data: Data) throws {}
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let directorID = JobDirector.ID(string: "1EjQHqaO86sbI65hHQ4KqW")!

    let director = try JobDirector(id: directorID,
                                   directory: FileManager.default.temporaryDirectory,
                                   typeResolver: typeResolver)

    let mainJob = MainJob()

    let jobID = JobID(string: "1d00nCKz4xs6vBwR9GmUAa")!

    func submit() async throws {

      func go() {
        director.submit(mainJob, id: jobID, expiration: .now.addingTimeInterval(30))
      }

      go()

      try await Task.sleep(for: .seconds(0.5))
    }

    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()
    try await submit()

    try await director.taskQueue.wait()
  }

}
