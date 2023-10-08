//
//  JobDirectorTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@testable import Kubrick
import PotentCodables
import XCTest


class JobDirectorTests: XCTestCase {

  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  func test_DynamicNonDuplicateJobs() async throws {

    struct DynamicJob: ExecutableJob {
      @JobInput var id: UniqueID = UniqueID()
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_DynamicNonDuplicateJobs.dynamic.executed"), object: nil)
      }
    }

    struct MainJob: SubmittableJob, Codable {
      @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs
      func execute() async {
        _ = await dynamicJobs.result(for: DynamicJob())
        _ = await dynamicJobs.result(for: DynamicJob())
      }
      init() {}
      init(from decoder: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_DynamicNonDuplicateJobs.dynamic.executed"), object: nil)
    executed.expectedFulfillmentCount = 2

    try await director.submit(MainJob())

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_DynamicDuplicateJobs() async throws {

    struct DynamicJob: ExecutableJob {
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_DynamicDuplicateJobs.dynamic.executed"), object: nil)
      }
    }

    struct MainJob: SubmittableJob {
      @JobEnvironmentValue(\.dynamicJobs) var dynamicJobs
      func execute() async {
        let job = DynamicJob()
        _ = await dynamicJobs.result(for: job)
        _ = await dynamicJobs.result(for: job)
      }
      init() {}
      init(from decoder: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_DynamicDuplicateJobs.dynamic.executed"), object: nil)
    executed.expectedFulfillmentCount = 1

    try await director.submit(MainJob())

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_Deduplication() async throws {

    struct MainJob: SubmittableJob {
      func execute() async {
        NotificationCenter.default.post(name: .init("test_Deduplication.main.executed"), object: nil)
      }
      init() {}
      init(from decoder: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_Deduplication.main.executed"), object: nil)
    executed.expectedFulfillmentCount = 2

    let mainJob = MainJob()
    let jobID = JobID(string: "7UDE7RgDFjRbZYqVpowU1m")!

    func submit() async throws {
      try await director.submit(mainJob, as: jobID, deduplicationWindow: .seconds(0.5))
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
      init(from decoder: Decoder) throws {}
      func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: AnyCodingKey.self)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let directorID = JobDirector.ID("1EjQHqaO86sbI65hHQ4KqW")!

    director = try JobDirector(id: directorID,
                               directory: FileManager.default.temporaryDirectory,
                               typeResolver: typeResolver)

    let mainJob = MainJob()

    let jobID = JobID(string: "1d00nCKz4xs6vBwR9GmUAa")!

    func submit() async throws {

      try await director.submit(mainJob, as: jobID, deduplicationWindow: .seconds(30))

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
