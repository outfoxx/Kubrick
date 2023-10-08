//
//  JobEnvironmentTests.swift
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


class JobEnvironmentTests: XCTestCase {

  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  public func test_CurrentJobKey() async throws {

    struct MainJob: SubmittableJob {
      @JobEnvironmentValue(\.currentJobKey) var currentJobKey
      func execute() async {
        NotificationCenter.default.post(name: .init("test_CurrentJobKey.main"),
                                        object: nil,
                                        userInfo: ["currentJobKey": currentJobKey])
      }
      init() {}
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let jobId = JobID(string: "1VKBaECrTxRNI2RpFkn7QT")!

    let executed = expectation(forNotification:  .init("test_CurrentJobKey.main"), object: nil) { not in
      return (not.userInfo?["currentJobKey"] as? JobKey)?.id == jobId
    }

    try await director.submit(MainJob(), as: jobId)

    await fulfillment(of: [executed], timeout: 3)
  }

  public func test_CurrentJobDirector() async throws {

    struct MainJob: SubmittableJob {
      @JobEnvironmentValue(\.currentJobDirector) var currentJobDirector
      func execute() async {
        NotificationCenter.default.post(name: .init("test_CurrentJobDirector.main"),
                                        object: nil,
                                        userInfo: ["currentJobDirector": currentJobDirector])
      }
      init() {}
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_CurrentJobDirector.main"), object: nil) { not in
      return (not.userInfo?["currentJobDirector"] as? JobDirector)?.id == self.director.id
    }

    try await director.submit(MainJob(), as: JobID(string: "76CNUDNhaVlaho9jxsttRD")!)

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
      init() {
        self.$value.bind(job: IntJob())
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_CurrentJobInputResults.main"),
                                        object: nil,
                                        userInfo: ["currentJobInputResults": currentJobInputResults])
      }
      init(from: Decoder) throws {}
      func encode(to encoder: Encoder) throws {}
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let executed = expectation(forNotification: .init("test_CurrentJobInputResults.main"), object: nil) { not in
      guard let currentJobInputResults = not.userInfo?["currentJobInputResults"] as? JobInputResults else {
        return false
      }
      guard case .success(let value) = currentJobInputResults.values.first, let value = value as? Int else {
        return false
      }
      return value == 12
    }

    try await director.submit(MainJob(), as: JobID(string: "76CNUDNhaVlaho9jxsttRD")!)

    await fulfillment(of: [executed], timeout: 3)
  }

}
