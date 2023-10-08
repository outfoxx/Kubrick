//
//  JobDirectorStoreTests.swift
//
//
//  Created by Kevin Wooten on 10/1/23.
//

import Foundation
@testable import Kubrick
import PotentCBOR
import XCTest


class JobDirectorStoreTests: XCTestCase {

  func test_StoreAndQueryResult() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {}
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let id = JobID.generate()
    let fingerprint = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))
    let key = JobKey(id: id, fingerprint: fingerprint)

    let data = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))

    let jobSaved = try await store.saveJob(MainJob(), as: id, deduplicationExpiration: Date())
    XCTAssertNotNil(jobSaved)

    try await store.updateValue(data, forKey: key)

    let queriedData = try await store.value(forKey: key)
    XCTAssertEqual(data, queriedData)
  }

  func test_RemoveResult() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {}
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let id = JobID.generate()
    let fingerprint = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))
    let key = JobKey(id: id, fingerprint: fingerprint)

    let jobSaved = try await store.saveJob(MainJob(), as: id, deduplicationExpiration: Date())
    XCTAssertNotNil(jobSaved)

    try await store.updateValue(Data(), forKey: key)

    do {
      let queriedData = try await store.value(forKey: key)
      XCTAssertNotNil(queriedData)
    }

    try await store.removeValue(forKey: key)

    do {
      let queriedData = try await store.value(forKey: key)
      XCTAssertNil(queriedData)
    }
  }

  func test_RemoveResults() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {}
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let id = JobID.generate()
    let fingerprint1 = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))
    let fingerprint2 = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))
    let fingerprint3 = try CBOREncoder.deterministic.encode(Int.random(in: .min ... .max))
    let key1 = JobKey(id: id, fingerprint: fingerprint1)
    let key2 = JobKey(id: id, fingerprint: fingerprint2)
    let key3 = JobKey(id: id, fingerprint: fingerprint3)

    let data1 = try CBOREncoder.default.encode(Int.random(in: .min ... .max))
    let data2 = try CBOREncoder.default.encode(Int.random(in: .min ... .max))
    let data3 = try CBOREncoder.default.encode(Int.random(in: .min ... .max))

    let jobSaved = try await store.saveJob(MainJob(), as: id, deduplicationExpiration: Date())
    XCTAssertNotNil(jobSaved)

    try await store.updateValue(data1, forKey: key1)
    try await store.updateValue(data2, forKey: key2)
    try await store.updateValue(data3, forKey: key3)

    do {
      let queriedData1 = try await store.value(forKey: key1)
      XCTAssertEqual(queriedData1, data1)

      let queriedData2 = try await store.value(forKey: key2)
      XCTAssertEqual(queriedData2, data2)

      let queriedData3 = try await store.value(forKey: key3)
      XCTAssertEqual(queriedData3, data3)
    }


    try await store.removeValue(forKey: key1)
    try await store.removeValue(forKey: key3)


    do {
      let queriedData1 = try await store.value(forKey: key1)
      XCTAssertNil(queriedData1)

      let queriedData2 = try await store.value(forKey: key2)
      XCTAssertEqual(queriedData2, data2)

      let queriedData3 = try await store.value(forKey: key3)
      XCTAssertNil(queriedData3)
    }
  }

  func test_QueryResultById() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {
      }
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let jobID = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID, deduplicationExpiration: Date())

    let jobKey1 = JobKey(id: jobID, fingerprint: Data(repeating: 1, count: 32))
    try await store.updateValue(Data(repeating: 1, count: 10), forKey: jobKey1)

    let jobKey2 = JobKey(id: jobID, fingerprint: Data(repeating: 2, count: 32))
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

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let jobID = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID, deduplicationExpiration: Date())

    let jobKey1 = JobKey(id: jobID, fingerprint: Data(repeating: 1, count: 32))
    try await store.updateValue(Data(repeating: 1, count: 10), forKey: jobKey1)

    let jobKey2 = JobKey(id: jobID, fingerprint: Data(repeating: 2, count: 32))
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

  func test_LoadJobs() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {
      }
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let jobID1 = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID1, deduplicationExpiration: Date())

    let jobID2 = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID2, deduplicationExpiration: Date())

    do {
      let results = try await store.loadJobs()
      XCTAssertEqual(results.count, 2)
      XCTAssertEqual(Set(results.map(\.id)), [jobID2, jobID1])
    }
  }

  func test_RemoveJobs() async throws {

    struct MainJob: SubmittableJob, Codable {
      func execute() async {
      }
    }

    let location = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("job-store")

    let store = try JobDirectorStore(location: location, jobTypeResolver: TypeNameTypeResolver(jobs: [MainJob.self]))

    let jobID1 = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID1, deduplicationExpiration: Date())

    let jobID2 = JobID()
    _ = try await store.saveJob(MainJob(), as: jobID2, deduplicationExpiration: Date())

    do {
      let results = try await store.loadJobs()
      XCTAssertEqual(results.count, 2)
    }

    try await store.removeJob(for: jobID1)

    do {
      let results = try await store.loadJobs()
      XCTAssertEqual(results.count, 1)
      XCTAssertEqual(results.first?.id, jobID2)
    }

    try await store.removeJob(for: jobID2)

    do {
      let results = try await store.loadJobs()
      XCTAssertEqual(results.count, 0)
    }
  }

}
