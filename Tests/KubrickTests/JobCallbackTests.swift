//
//  JobCallbackTests.swift
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


class JobCallbackTests: XCTestCase {

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

  func test_FinishedCalled() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {}

      func finished() async {
        NotificationCenter.default.post(name: .init("test_FinishedCalled.finished"), object: nil)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    try await director.start()

    let finishedEx = expectation(forNotification: .init("test_FinishedCalled.finished"), object: nil)

    try await director.submit(MainJob())

    await fulfillment(of: [finishedEx], timeout: 3)
  }
}
