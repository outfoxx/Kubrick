//
//  MapJobTests.swift
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


class MapJobTests: XCTestCase {

  enum TestError: Error {
    case test
  }

  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  func test_MappingValuesToDifferentTypes() async throws {

    struct IntJob: ResultJob {
      func execute() async throws -> Int {
        return 1
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var text: String
      init() {
        self.$text.bind {
          IntJob()
            .map { count in
              String(count * 10)
            }
        }
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_MappingValuesToDifferentTypes.main"),
                                        object: nil,
                                        userInfo: ["text": text])
      }
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_MappingValuesToDifferentTypes.main"), object: nil) { not in
      return (not.userInfo?["text"] as? String) == "10"
    }

    try await director.submit(MainJob(), as: JobID(string: "5Al02cjKTL9tmf2tT3uhEy")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_MappingValuesToResults() async throws {

    struct IntJob: ResultJob {
      func execute() async throws -> Int {
        return 1
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: ExecuteResult<Int>
      init() {
        self.$count.bind {
          IntJob()
            .mapToResult()
        }
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_MappingValuesToResults.main"),
                                        object: nil,
                                        userInfo: ["result": count])
      }

      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_MappingValuesToResults.main"), object: nil) { not in
      guard 
        let result = not.userInfo?["result"] as? ExecuteResult<Int>,
        case .success(let count) = result
      else {
        return false
      }
      return count == 1
    }

    try await director.submit(MainJob(), as: JobID(string: "443EQfOK5xoUbZsPs6tuBW")!)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_MappingErrorsToResults() async throws {

    struct ThrowingJob: ResultJob {
      func execute() async throws -> Int {
        throw TestError.test
      }
    }

    struct MainJob: SubmittableJob {
      @JobInput var count: ExecuteResult<Int>
      init() {
        self.$count.bind {
          ThrowingJob()
            .mapToResult()
        }
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_MappingErrorsToResults.main"),
                                        object: nil,
                                        userInfo: ["result": count])
      }
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_MappingErrorsToResults.main"), object: nil) { not in
      guard
        let result = not.userInfo?["result"] as? ExecuteResult<Int>,
        case .failure(let error) = result
      else {
        return false
      }
      return error as NSError == TestError.test as NSError
    }

    try await director.submit(MainJob(), as: JobID(string: "6qkMuVF6Vtim7TEd3OXvIf")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
