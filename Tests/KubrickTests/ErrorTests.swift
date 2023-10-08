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
import PotentCodables
import XCTest


class ErrorTests: XCTestCase {

  enum TestError: Error, Codable, Equatable {
    case test
    case test2
  }

  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  func test_JobInputResultsFailureMapsToSingleFailureIgnoringCancellation() {

    let inputs: JobInputResults = [
      UUID(): .failure(CancellationError()),
      UUID(): .failure(TestError.test),
      UUID(): .failure(CancellationError())
    ]

    guard let failure = inputs.failure else {
      return XCTFail("Failure should not be nil")
    }

    switch failure {
    case TestError.test:
      break
    default:
      XCTFail("Unexpected error type")
    }
  }

  func test_ErrorBoxKnownTypes() throws {

    let typeResolver = TypeNameTypeResolver(jobs: [], errors: [TestError.self])

    let decoder = JSONDecoder()
    decoder.userInfo[submittableJobTypeResolverKey] = typeResolver
    decoder.userInfo[jobErrorTypeResolverKey] = typeResolver

    let encoder = JSONEncoder()
    encoder.userInfo[submittableJobTypeResolverKey] = typeResolver
    encoder.userInfo[jobErrorTypeResolverKey] = typeResolver

    let error = TestError.test
    let encodedBox = try encoder.encode(JobErrorBox(error))
    let decodedBox = try decoder.decode(JobErrorBox.self, from: encodedBox)

    do {
      throw decodedBox.error
    }
    catch TestError.test {
      // Worked!
    }
    catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func test_ErrorBoxKnownUnknownTypes() throws {

    let typeResolver = TypeNameTypeResolver(jobs: [], errors: [TestError.self])

    let decoder = JSONDecoder()

    let encoder = JSONEncoder()
    encoder.userInfo[submittableJobTypeResolverKey] = typeResolver
    encoder.userInfo[jobErrorTypeResolverKey] = typeResolver

    let error = TestError.test
    let encodedBox = try encoder.encode(JobErrorBox(error))

    do {
      _ = try decoder.decode(JobErrorBox.self, from: encodedBox)
    }
    catch is DecodingError {
      // Worked!
    }
    catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func test_ErrorBoxUnknownTypes() throws {

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    let error = TestError.test
    let encodedBox = try encoder.encode(JobErrorBox(error))
    let decodedBox = try decoder.decode(JobErrorBox.self, from: encodedBox)

    XCTAssertTrue(type(of: decodedBox.error) == NSError.self)
    XCTAssertEqual(decodedBox.error as NSError, error as NSError)
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

      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: AnyCodingKey.self)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    try await director.submit(MainJob(), as: JobID(string: "1hN7K3p95FQHn3CD2n7WW7")!)

    try await director.waitForCompletionOfCurrentJobs(timeout: 3)

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

      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: AnyCodingKey.self)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let onCancelled = expectation(description: "NeverEndingJob Cancelled")

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    try await director.submit(MainJob { onCancelled.fulfill() }, as: JobID(string: "75AtTO40PzFkM11yULcgD")!)

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

      init() {
        self.$count.bind {
          ThrowingJob()
            .catch { _ in
              return -1
            }
        }
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_CatchMapsErrorsToValues.main.execute"),
                                        object: nil,
                                        userInfo: ["count": count])
      }

      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_CatchMapsErrorsToValues.main.execute"), object: nil) { not in
      return not.userInfo?["count"] as? Int == -1
    }

    try await director.submit(MainJob(), as: JobID(string: "5u91kxIdJ6MwUrpf1xRWqS")!)

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

      init() {
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
        NotificationCenter.default.post(name: .init("test_CatchErrorsAreReported.main.failed"),
                                        object: nil,
                                        userInfo: ["error": error])
        return .failure(error)
      }

      func execute() async {
        XCTFail("Should not be called")
      }

      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_CatchErrorsAreReported.main.failed"), object: nil) { not in
      return not.userInfo?["error"] as? NSError == (TestError.test2 as NSError)
    }

    try await director.submit(MainJob(), as: JobID(string: "4uZPZbKGZZWstJe7rEdW6c")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
