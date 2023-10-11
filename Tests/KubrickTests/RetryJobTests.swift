//
//  RetryJobTests.swift
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


class RetryJobTests: XCTestCase {

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
  
  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  func test_RetryTree() async throws {

    struct DependencyJob: ExecutableJob {
      @JobInput var id = UniqueID()
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_RetryTree.dep"), object: nil)
      }
    }

    struct RetriedJob: ResultJob {
      @JobInput var id = UniqueID()
      @JobInput var dep: NoValue
      let counter = Counter()
      let failUnder: Int
      init(failUnder: Int) {
        self.failUnder = failUnder
        self.$dep.bind(job: DependencyJob())
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
      init() {
        self.$count1.bind {
          RetriedJob(failUnder: 4)
            .retry(maxAttempts: 10)
        }
        self.$count2.bind {
          RetriedJob(failUnder: 1)
            .retry(maxAttempts: 10)
        }
      }
      func execute() async {}
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let depExecuted = expectation(forNotification: .init("test_RetryTree.dep"), object: nil)
    depExecuted.expectedFulfillmentCount = 5

    try await director.submit(MainJob(), deduplicationWindow: .seconds(20))

    await fulfillment(of: [depExecuted], timeout: 3)
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
      init() {
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
        NotificationCenter.default.post(name: .init("test_RetryUniqueInputs.main"),
                                        object: nil,
                                        userInfo: ["total": count1 + count2])
      }

      init(from: Decoder) throws { self.init() }
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_RetryUniqueInputs.main"), object: nil) { not in
      return (not.userInfo?["total"] as? Int) == 5
    }

    try await director.submit(MainJob())

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_RetryDuplicateInputs() async throws {

    struct RetriedJob: ResultJob {
      let counter: Counter
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
      init() {
        let counter = Counter()
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
        NotificationCenter.default.post(name: .init("test_RetryDuplicateInputs.main"),
                                        object: nil,
                                        userInfo: ["total": count1 + count2])
      }
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_RetryDuplicateInputs.main"), object: nil) { not in
      return (not.userInfo?["total"] as? Int) == 8
    }

    try await director.submit(MainJob())

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_RetriesFail() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.lowCount
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: ExecuteResult<Int>
      init() {
        self.$count.bind {
          ThrowingJob()
            .retry(maxAttempts: 2)
            .mapToResult()
        }
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_RetriesFail.main"), object: nil, userInfo: ["count": count])
      }
      init(from: Decoder) throws { self.init() }
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_RetriesFail.main"), object: nil) { not in
      guard 
        let count = not.userInfo?["count"] as? ExecuteResult<Int>,
        case .failure(let error) = count
      else {
        return false
      }
      return error as NSError == TestError.lowCount as NSError
    }

    try await director.submit(MainJob())

    await fulfillment(of: [executed], timeout: 3)
  }

}
