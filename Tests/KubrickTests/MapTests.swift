//
//  MapTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation
@testable import Kubrick
import XCTest


class MapTests: XCTestCase {

  enum TestError: Swift.Error {
    case test
  }

  func test_MappingValuesToDifferentTypes() async throws {

    struct IntJob: ResultJob {
      func execute() async throws -> Int {
        return 1
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var text: String

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (String) -> Void

      init(onExecute: @escaping (String) -> Void) {
        self.onExecute = onExecute
        self.$text.bind {
          IntJob()
            .map { count in
              String(count * 10)
            }
        }
      }

      func execute() async {
        onExecute(text)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let mainJob = MainJob {
      XCTAssertEqual($0, "10")
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "5Al02cjKTL9tmf2tT3uhEy")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_MappingValuesToResults() async throws {

    struct IntJob: ResultJob {
      func execute() async throws -> Int {
        return 1
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: Result<Int, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<Int, Error>) -> Void

      init(onExecute: @escaping (Result<Int, Error>) -> Void) {
        self.onExecute = onExecute
        self.$count.bind {
          IntJob()
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(count)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let mainJob = MainJob {
      guard case .success(let count) = $0 else {
        return XCTFail("MainJob should have succeeded")
      }
      XCTAssertEqual(count, 1)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "443EQfOK5xoUbZsPs6tuBW")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_MappingErrorsToResults() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: Result<Int, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<Int, Error>) -> Void

      init(onExecute: @escaping (Result<Int, Error>) -> Void) {
        self.onExecute = onExecute
        self.$count.bind {
          ThrowingJob()
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(count)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let mainJob = MainJob {
      guard case .failure(let error) = $0 else {
        return XCTFail("MainJob should have failed")
      }
      XCTAssertEqual(error as NSError, TestError.test as NSError)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "6qkMuVF6Vtim7TEd3OXvIf")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
