//
//  ErrorTests.swift
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


class ErrorTests: XCTestCase {

  enum TestError: Error {
    case test
    case test2
  }

  func test_ExecuteNotCalledWhenFailingInputs() async throws {

    struct ThrowingJob: ExecutableJob {
      func execute() async throws {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var throwing: NoValue
      init() {
        self.$throwing.bind {
          ThrowingJob()
        }
      }

      func execute() async {
        XCTFail("Should not be called")
      }

      init(data: Data) throws {}
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)

    try await director.submit(MainJob(), id: JobID(string: "1hN7K3p95FQHn3CD2n7WW7")!)

    // Ensure MainJob was completed
    let jobCount = try await director.submittedJobCount
    XCTAssertEqual(jobCount, 0)
  }

  func test_FailingInputsCancelAllResolvingInputs() async throws {

    struct NeverEndingJob: ExecutableJob {
      let onCancel: () -> Void
      func execute() async throws {
        do {
          try await AsyncSemaphore(value: 0).wait()
        }
        catch {
          onCancel()
          throw error
        }
      }
    }

    struct ThrowingJob: ExecutableJob {
      func execute() async throws {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var throwing: NoValue
      @JobInput var neverEnding: NoValue
      init(onCancel: @escaping () -> Void) {
        self.$throwing.bind {
          ThrowingJob()
        }
        self.$neverEnding.bind {
          NeverEndingJob(onCancel: onCancel)
        }
      }

      func execute() async {
        XCTFail("Should not be called")
      }

      init(data: Data) throws {}
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let onCancelled = expectation(description: "NeverEndingJob Cancelled")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)

    try await director.submit(MainJob { onCancelled.fulfill() }, id: JobID(string: "75AtTO40PzFkM11yULcgD")!)

    await fulfillment(of: [onCancelled], timeout: 3)
  }

  func test_CatchMapsErrorsToValues() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: Int

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Int) -> Void

      init(onExecute: @escaping (Int) -> Void) {
        self.onExecute = onExecute
        self.$count.bind {
          ThrowingJob()
            .catch { _ in
              return -1
            }
        }
      }

      func execute() async {
        onExecute(count)
      }

      init(data: Data) throws {
        onExecute = { _ in }
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let executed = expectation(description: "MainJob executed")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)

    let mainJob = MainJob {
      XCTAssertEqual($0, -1)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "5u91kxIdJ6MwUrpf1xRWqS")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_CatchErrorsAreReported() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: Int

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onFailed: (Error) -> Void

      init(onFailed: @escaping (Error) -> Void) {
        self.onFailed = onFailed
        self.$count.bind {
          ThrowingJob()
            .catch { _ in
              throw TestError.test2
            }
        }
      }

      func execute(
        as jobKey: JobKey,
        with inputResults: JobInputResults,
        for director: JobDirector
      ) async throws -> JobResult<NoValue> {
        guard case .failure(let error) = inputResults.values.first else {
          XCTFail("Input should have failed")
          return .failure(TestError.test)
        }
        onFailed(error)
        return .failure(error)
      }

      func execute() async {
        XCTFail("Should not be called")
      }

      init(data: Data) throws {
        onFailed = { _ in }
      }
      func encode() throws -> Data { Data() }
    }

    let typeResolver = TypeNameJobTypeResolver(types: [
      MainJob.self
    ])

    let executed = expectation(description: "MainJob executed")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)

    let mainJob = MainJob { error in
      XCTAssertEqual(error as NSError, TestError.test2 as NSError)
      executed.fulfill()
    }

    try await director.submit(mainJob, id: JobID(string: "4uZPZbKGZZWstJe7rEdW6c")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
