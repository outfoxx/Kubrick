//
//  EnvironmentTests.swift
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


public class EnvironmentTest: XCTestCase {

  public func test_CurrentJobKey() async throws {

    struct MainJob: SubmittableJob {

      @JobEnvironmentValue(\.currentJobKey) var currentJobKey

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (JobKey) -> Void

      init(onExecute: @escaping (JobKey) -> Void) {
        self.onExecute = onExecute
      }

      func execute() async {
        onExecute(currentJobKey)
      }

      init(data: Data) throws {
        onExecute = { _ in }
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let jobId = JobID(string: "1VKBaECrTxRNI2RpFkn7QT")!

    let mainJob = MainJob { jobKey in
      XCTAssertEqual(jobKey.submission, jobId)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: jobId)

    await fulfillment(of: [executed], timeout: 3)
  }

  public func test_CurrentJobDirector() async throws {

    struct MainJob: SubmittableJob {

      @JobEnvironmentValue(\.currentJobDirector) var currentJobDirector

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (JobDirector) -> Void

      init(onExecute: @escaping (JobDirector) -> Void) {
        self.onExecute = onExecute
      }

      func execute() async {
        onExecute(currentJobDirector)
      }

      init(data: Data) throws {
        onExecute = { _ in }
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let mainJob = MainJob {
      XCTAssertEqual(director.id, $0.id)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "76CNUDNhaVlaho9jxsttRD")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  public func test_CurrentJobInputResults() async throws {

    struct IntJob: ResultJob {
      func execute() async throws -> Int {
        return 12
      }
    }

    struct MainJob: SubmittableJob {

      @JobInput var value: Int
      @JobEnvironmentValue(\.currentJobInputResults) var currentJobInputResults

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (JobInputResults) -> Void

      init(onExecute: @escaping (JobInputResults) -> Void) {
        self.onExecute = onExecute
        self.$value.bind(job: IntJob())
      }

      func execute() async {
        onExecute(currentJobInputResults)
      }

      init(data: Data) throws {
        onExecute = { _ in }
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let mainJob = MainJob {
      XCTAssertEqual($0.count, 1)
      guard case .success(let value) = $0.values.first, let value = value as? Int else {
        return XCTFail("Inputs should have a single integer result")
      }
      XCTAssertEqual(value, 12)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "76CNUDNhaVlaho9jxsttRD")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
