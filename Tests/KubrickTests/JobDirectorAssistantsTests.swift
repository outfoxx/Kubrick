//
//  JobDirectorAssistantsTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@testable import Kubrick
import OSLog
import XCTest


class JobDirectorAssistantsTests: XCTestCase {

  let location = FileManager.default.temporaryDirectory.appendingPathComponent(UniqueID.generateString())
  var director: JobDirector!
  var assistant: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
    if let assistant {
      try await assistant.stop()
      self.assistant = nil
    }
  }

  func test_AssistantDirectoryLocation() {

    let jobID = JobDirectorID.generate()

    XCTAssertEqual(try JobDirector.storeLocation(id: jobID, in: location, type: .assistant(name: "tester")),
                   location.appendingPathComponent("\(jobID).job-store/assistants/tester"))
  }

  func test_UnlockedAssistantJobsAreFound() async throws {

    let transferEx = expectation(description: "Transferred")
    transferEx.expectedFulfillmentCount = 2

    let assistantsLocation = location.appendingPathComponent("assistants")
    try FileManager.default.createDirectory(at: assistantsLocation, withIntermediateDirectories: true)

    let watcher = try AssistantsWatcher(assistantsLocation: assistantsLocation)
    try await watcher.start { jobURL in
      transferEx.fulfill()
    }

    let ass1 = assistantsLocation.appendingPathComponent("ass1/jobs")

    let ass1Job = ass1.appendingPathComponent("test.job")
    try FileManager.default.createDirectory(at: ass1Job,
                                            withIntermediateDirectories: true)

    let ass2 = assistantsLocation.appendingPathComponent("ass2/jobs")

    let ass2Job = ass2.appendingPathComponent("test.job")
    try FileManager.default.createDirectory(at: ass2Job,
                                            withIntermediateDirectories: true)

    try await Task.sleep(seconds: 0.2)
    
    let ass1JobLock = try FileHandle(forDirectory: ass1Job)
    try ass1JobLock.lock()
    try ass1JobLock.unlock()

    let ass2JobLock = try FileHandle(forDirectory: ass2Job)
    try ass2JobLock.lock()
    try ass2JobLock.unlock()


    await fulfillment(of: [transferEx], timeout: 5)
  }

  func test_ManualJobTransfer() async throws {

    let depEx = expectation(forNotification: .init(rawValue: "test_ManualJobTransfer.dep"), object: nil)

    let txfrEx = expectation(forNotification: .init(rawValue: "test_ManualJobTransfer.txfr"), object: nil)
    txfrEx.expectedFulfillmentCount = 2

    let mainEx = expectation(forNotification: .init(rawValue: "test_ManualJobTransfer.main"), object: nil)

    struct DepJob: ExecutableJob {
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_ManualJobTransfer.dep"), object: nil)
      }
    }

    struct TxfrJob: ExecutableJob {
      @JobEnvironmentValue(\.currentJobDirector) var director
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_ManualJobTransfer.txfr"), object: nil)
        try director.transferToPrincipal()
      }
    }

    struct MainJob: SubmittableJob, Codable {
      @JobInput var dep: NoValue
      @JobInput var txfr: NoValue
      init() {
        self.$dep.bind(job: DepJob())
        self.$txfr.bind(job: TxfrJob())
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_ManualJobTransfer.main"), object: nil)
      }
      init(from decoder: Decoder) throws { self.init() }
      func encode(to encoder: Encoder) throws {}
    }

    let directorID = JobDirectorID.generate()
    let typeRes = TypeNameTypeResolver(jobs: [MainJob.self])

    director = try JobDirector(id: directorID,
                               directory: location,
                               typeResolver: typeRes)
    try await director.start()

    assistant = try JobDirector(id: directorID,
                                directory: location,
                                type: .assistant(name: "test"),
                                typeResolver: typeRes)
    try await assistant.start()

    try await assistant.submit(MainJob())

    await fulfillment(of: [depEx, txfrEx, mainEx], timeout: 5)
  }

  func test_AutomaticJobTransfer() async throws {

    let depEx = expectation(forNotification: .init(rawValue: "test_AutomaticJobTransfer.dep"), object: nil)

    let txfrEx = expectation(forNotification: .init(rawValue: "test_AutomaticJobTransfer.txfr"), object: nil)

    let mainEx = expectation(forNotification: .init(rawValue: "test_AutomaticJobTransfer.main"), object: nil)

    struct DepJob: ExecutableJob {
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_AutomaticJobTransfer.dep"), object: nil)
      }
    }

    struct TxfrJob: ExecutableJob {
      @JobEnvironmentValue(\.currentJobDirector) var director
      func execute() async throws {
        NotificationCenter.default.post(name: .init("test_AutomaticJobTransfer.txfr"), object: nil)
        try director.transferToPrincipal()
      }
    }

    struct MainJob: SubmittableJob, Codable {
      @JobInput var dep: NoValue
      @JobInput var txfr: NoValue
      init() {
        self.$dep.bind(job: DepJob())
        self.$txfr.bind(job: TxfrJob())
      }
      func execute() async {
        NotificationCenter.default.post(name: .init("test_AutomaticJobTransfer.main"), object: nil)
      }
      init(from decoder: Decoder) throws { self.init() }
      func encode(to encoder: Encoder) throws {}
    }

    let directorID = JobDirectorID.generate()
    let typeRes = TypeNameTypeResolver(jobs: [MainJob.self])

    director = try JobDirector(id: directorID,
                               directory: location,
                               typeResolver: typeRes)

    assistant = try JobDirector(id: directorID,
                                directory: location,
                                type: .assistant(name: "test"),
                                typeResolver: typeRes)

    _ = try await assistant.store.saveJob(MainJob(), as: JobID.generate(), deduplicationExpiration: .now)

    try await director.start()

    await fulfillment(of: [depEx, txfrEx, mainEx], timeout: 5)
  }

}
