//
//  DirectorStoreTests.swift
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

class DirectorStoreTests: XCTestCase {

  func test_QueryResultBySubmission() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {
      }
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, typeResolver: TypeNameJobTypeResolver(types: []))

    let jobID = JobID()
    _ = try await store.saveJob(MainJob(), id: jobID, expiration: .now)

    let jobKey1 = JobKey(submission: jobID, fingerprint: Data(repeating: 1, count: 32))
    try await store.updateValue(Data(repeating: 1, count: 10), forKey: jobKey1)

    let jobKey2 = JobKey(submission: jobID, fingerprint: Data(repeating: 2, count: 32))
    try await store.updateValue(Data(repeating: 2, count: 10), forKey: jobKey2)

    do {
      let results = try await store.loadJobResults(for: jobID)
      XCTAssertEqual(results.count, 2)
    }
  }

  func test_DeletingSubmittedJobDeletesResults() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {
      }
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, typeResolver: TypeNameJobTypeResolver(types: []))

    let jobID = JobID()
    _ = try await store.saveJob(MainJob(), id: jobID, expiration: .now)

    let jobKey1 = JobKey(submission: jobID, fingerprint: Data(repeating: 1, count: 32))
    try await store.updateValue(Data(repeating: 1, count: 10), forKey: jobKey1)

    let jobKey2 = JobKey(submission: jobID, fingerprint: Data(repeating: 2, count: 32))
    try await store.updateValue(Data(repeating: 2, count: 10), forKey: jobKey2)

    do {
      let results = try await store.loadJobResults(for: jobID)
      XCTAssertEqual(results.count, 2)
    }

    try await store.removeJob(for: jobID)

    do {
      let results = try await store.loadJobResults(for: jobID)
      XCTAssertEqual(results.count, 0)
    }
  }

}
