//
//  RetryTests.swift
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


class RetryTests: XCTestCase {

  enum TestError: Error {
    case lowCount
  }

  actor Counter {
    var count: Int = 0

    func increment() -> Int {
      count += 1
      return count
    }
  }

  func test_RetryUniqueInputs() async throws {

    struct RetriedJob: ResultJob {
      @JobInput var id = UniqueID()
      let counter = Counter()
      let failUnder: Int

      init(failUnder: Int) {
        self.failUnder = failUnder
      }

      func execute() async throws -> Int {
        let count = await counter.increment()
        if count < failUnder {
          throw TestError.lowCount
        }
        return count
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count1: Int
      @JobInput var count2: Int

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Int) -> Void

      init(onExecute: @escaping (Int) -> Void) {
        self.onExecute = onExecute
        self.$count1.bind {
          RetriedJob(failUnder: 4)
            .retry(maxAttempts: 10)
        }
        self.$count2.bind {
          RetriedJob(failUnder: 1)
            .retry(maxAttempts: 10)
        }
      }

      func execute() async {
        onExecute(count1 + count2)
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

    let id = JobID()

    let mainJob = MainJob {
      XCTAssertEqual($0, 5)
      executed.fulfill()
    }

    await director.submit(mainJob, id: id)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_RetryDuplicateInputs() async throws {

    struct RetriedJob: ResultJob {
      let counter: Counter

      init(counter: Counter) {
        self.counter = counter
      }

      func execute() async throws -> Int {
        let count = await counter.increment()
        if count < 4 {
          throw TestError.lowCount
        }
        return count
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count1: Int
      @JobInput var count2: Int

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Int) -> Void

      init(counter: Counter, onExecute: @escaping (Int) -> Void) {
        self.onExecute = onExecute
        self.$count1.bind {
          RetriedJob(counter: counter)
            .retry(maxAttempts: 10)
        }
        self.$count2.bind {
          RetriedJob(counter: counter)
            .retry(maxAttempts: 10)
        }
      }

      func execute() async {
        onExecute(count1 + count2)
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

    let id = JobID()
    let counter = Counter()
    let mainJob = MainJob(counter: counter) {
      XCTAssertEqual($0, 8)
      executed.fulfill()
    }

    await director.submit(mainJob, id: id)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_RetriesFail() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.lowCount
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
            .retry(maxAttempts: 2)
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

    let id = JobID()
    let mainJob = MainJob {
      guard case .failure(let error) = $0 else {
        return XCTFail("Input should have failed")
      }
      XCTAssertEqual(error as NSError, TestError.lowCount as NSError)
      executed.fulfill()
    }

    await director.submit(mainJob, id: id)

    await fulfillment(of: [executed], timeout: 3)
  }

}
