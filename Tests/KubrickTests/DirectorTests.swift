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

  func test_DynamicNonDuplicateJobs() async throws {

    struct DynamicJob: ExecutableJob {

      @JobInput var id: UniqueID
      let onExecute: () -> Void

      init(onExecute: @escaping () -> Void) {
        self.id = UniqueID()
        self.onExecute = onExecute
      }

      func execute() async throws {
        onExecute()
      }

    }

    struct MainJob: SubmittableJob {

      @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: () -> Void

      init(onExecute: @escaping () -> Void) {
        self.onExecute = onExecute
      }

      func execute() async {
        _ = await dynamicJobs.result(for: DynamicJob(onExecute: onExecute))
        _ = await dynamicJobs.result(for: DynamicJob(onExecute: onExecute))
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = {}
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")
    executed.expectedFulfillmentCount = 2

    let mainJob = MainJob {
      executed.fulfill()
    }

    try await director.submit(mainJob)

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_DynamicDuplicateJobs() async throws {

    struct DynamicJob: ExecutableJob {

      let onExecute: () -> Void

      init(onExecute: @escaping () -> Void) {
        self.onExecute = onExecute
      }

      func execute() async throws {
        onExecute()
      }

    }

    struct MainJob: SubmittableJob {

      @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: () -> Void

      init(onExecute: @escaping () -> Void) {
        self.onExecute = onExecute
      }

      func execute() async {
        let job = DynamicJob(onExecute: onExecute)
        _ = await dynamicJobs.result(for: job)
        _ = await dynamicJobs.result(for: job)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = {}
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")
    executed.expectedFulfillmentCount = 1

    let mainJob = MainJob {
      executed.fulfill()
    }

    try await director.submit(mainJob)

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

    await fulfillment(of: [executed], timeout: 3)
  }

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

      init(from: Data, using: any JobDecoder) throws {
        onExecute = {}
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")
    executed.expectedFulfillmentCount = 2

    let mainJob = MainJob {
      executed.fulfill()
    }

    let jobID = JobID(string: "7UDE7RgDFjRbZYqVpowU1m")!

    func submit() async throws {

      try await director.submit(mainJob, id: jobID, deduplicationWindow: .seconds(0.5))

      try await Task.sleep(seconds: 0.1)
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

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

    await fulfillment(of: [executed], timeout: 3)
  }

  func interactive_test_LongDeduplication() async throws {

    struct MainJob: SubmittableJob {
      init() {}
      func execute() async { print("🎉 Executing") }
      init(from: Data, using: any JobDecoder) throws {}
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let directorID = JobDirector.ID("1EjQHqaO86sbI65hHQ4KqW")!

    let director = try JobDirector(id: directorID,
                                   directory: FileManager.default.temporaryDirectory,
                                   typeResolver: typeResolver)

    let mainJob = MainJob()

    let jobID = JobID(string: "1d00nCKz4xs6vBwR9GmUAa")!

    func submit() async throws {

      try await director.submit(mainJob, id: jobID, deduplicationWindow: .seconds(30))

      try await Task.sleep(seconds: 0.5)
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

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)
  }

}
