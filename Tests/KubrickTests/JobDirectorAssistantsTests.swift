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
import Sunday
import SundayServer
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

    XCTAssertEqual(try JobDirector.storeLocation(id: jobID, in: location, mode: .assistant(name: "tester")),
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
                                mode: .assistant(name: "test"),
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
                                mode: .assistant(name: "test"),
                                typeResolver: typeRes)

    _ = try await assistant.store.saveJob(MainJob(), as: JobID.generate(), deduplicationExpiration: .now)

    try await director.start()

    await fulfillment(of: [depEx, txfrEx, mainEx], timeout: 5)
  }

  func test_DownloadJobTransferred() async throws {

    let testServer = try RoutingHTTPServer {
      Path("/test-file") {
        GET { _, response in

          response
            .start(status: .ok, headers: [
              HTTP.StdHeaders.contentType: [MediaType.octetStream.value],
              HTTP.StdHeaders.contentLength: [(1024 * 512).description],
            ])

          let chunk = Data((0..<1024).map { _ in UInt8.random(in: .min ..< .max) })

          for chunkIdx in 1 ... 512 {
            response.server.queue.asyncAfter(deadline: .now().advanced(by: .milliseconds(chunkIdx * 2))) {
              response.send(body: chunk, final: chunkIdx >= 512)
            }
          }
        }
      }
    }

    guard let serverURL = testServer.startLocal(timeout: 1) else {
      return XCTFail("Unable to start server")
    }

    struct MainJob: SubmittableJob {
      @JobInput var url: URL
      @JobInput var download: URLSessionDownloadJobResult

      init(url: URL) {
        self.url = url
        self.$download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .onStart { director, _ in
              NotificationCenter.default.post(name: .init("test_DownloadJobTransferred.download.started"), object: nil)
              try director.transferToPrincipal()
            }
            .onProgress(Self.onProgress)
        }
      }

      static func onProgress(progressedBytes: Int, transferredBytes: Int, totalBytes: Int) {
        NotificationCenter.default.post(name: .init("test_DownloadJobTransferred.main.progressed"),
                                        object: nil,
                                        userInfo: [
                                          "progressed": progressedBytes,
                                          "transferred": transferredBytes,
                                          "total": totalBytes
                                        ])
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_DownloadJobTransferred.main.executed"),
                                        object: nil,
                                        userInfo: ["download": download])
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(url: try container.decode(URL.self))
      }

      func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let requestURL = serverURL.appendingPathComponent("test-file")

    let directorID = JobDirectorID.generate()

    let primarySessionConfig = URLSessionConfiguration.background(withIdentifier: "\(directorID).primary")
    let secondarySessionConfig = URLSessionConfiguration.background(withIdentifier: "\(directorID).secondary")

    director = try JobDirector(id: directorID,
                               directory: FileManager.default.temporaryDirectory,
                               mode: .principal,
                               typeResolver: typeResolver)

    let directorURLSessionJobManager = URLSessionJobManager(director: director,
                                                            primaryConfiguration: primarySessionConfig)
    await directorURLSessionJobManager.addSecondarySession(configuration: secondarySessionConfig)
    director.injected[URLSessionJobManager.self] = directorURLSessionJobManager


    assistant = try JobDirector(id: directorID,
                                directory: FileManager.default.temporaryDirectory,
                                mode: .assistant(name: "test"),
                                typeResolver: typeResolver)

    let assistantURLSessionJobManager = URLSessionJobManager(director: assistant,
                                                             primaryConfiguration: secondarySessionConfig)
    assistant.injected[URLSessionJobManager.self] = assistantURLSessionJobManager


    try await director.start()
    try await assistant.start()


    let startedEx = expectation(forNotification: .init("test_DownloadJobTransferred.download.started"), object: nil)

    let progressedEx = expectation(forNotification: .init("test_DownloadJobTransferred.main.progressed"), object: nil)
    progressedEx.expectedFulfillmentCount = 3
    progressedEx.assertForOverFulfill = false

    let executedEx = expectation(forNotification: .init("test_DownloadJobTransferred.main.executed"),
                                 object: nil) { not in
      guard
        let download = not.userInfo?["download"] as? URLSessionDownloadJobResult,
        let fileSize = try? download.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        fileSize == 1024 * 512
      else {
        return false
      }

      return download.response.statusCode == 200 && download.response.url == requestURL
    }

    try await assistant.submit(MainJob(url: requestURL))

    await fulfillment(of: [startedEx, progressedEx, executedEx], timeout: 3)
  }

  func test_UploadJobTransferred() async throws {

    let testServer = try RoutingHTTPServer {
      Path("/test-file") {
        PUT { request, response in
          XCTAssertEqual(request.body?.count, 512 * 1024)
          response.server.queue.asyncAfter(deadline: .now().advanced(by: .milliseconds(1500))) {
            response.send(status: .ok)
          }
        }
      }
    }

    guard let serverURL = testServer.startLocal(timeout: 1) else {
      return XCTFail("Unable to start server")
    }

    struct MainJob: SubmittableJob {
      @JobInput var fromFile: URL
      @JobInput var toURL: URL
      @JobInput var response: URLSessionJobResponse

      init(fromFile: URL, toURL: URL) {
        self.fromFile = fromFile
        self.toURL = toURL
        self.$response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: toURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .onStart { director, _ in
              NotificationCenter.default.post(name: .init("test_UploadJobTransferred.upload.started"), object: nil)
              try director.transferToPrincipal()
            }
            .onProgress(Self.onProgress)
        }
      }

      static func onProgress(progressedBytes: Int, transferredBytes: Int, totalBytes: Int) {
        NotificationCenter.default.post(name: .init("test_UploadJobTransferred.main.progressed"),
                                        object: nil,
                                        userInfo: [
                                          "progressed": progressedBytes,
                                          "transferred": transferredBytes,
                                          "total": totalBytes
                                        ])
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_UploadJobTransferred.main.executed"),
                                        object: nil,
                                        userInfo: ["response": response])
      }

      enum CodingKeys: CodingKey {
        case fromFile
        case toURL
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
          fromFile: try container.decode(URL.self, forKey: .fromFile),
          toURL: try container.decode(URL.self, forKey: .toURL)
        )
      }

      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromFile, forKey: .fromFile)
        try container.encode(toURL, forKey: .toURL)
      }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let requestURL = serverURL.appendingPathComponent("test-file")

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("data")
    try Data((0 ..< 512 * 1024).map { _ in UInt8.random(in: .min ..< .max) })
      .write(to: fileURL)

    let directorID = JobDirectorID.generate()

    let primarySessionConfig = URLSessionConfiguration.background(withIdentifier: "\(directorID).primary")
    let secondarySessionConfig = URLSessionConfiguration.background(withIdentifier: "\(directorID).secondary")

    director = try JobDirector(id: directorID,
                               directory: FileManager.default.temporaryDirectory,
                               mode: .principal,
                               typeResolver: typeResolver)

    let directorURLSessionJobManager = URLSessionJobManager(director: director,
                                                            primaryConfiguration: primarySessionConfig)
    await directorURLSessionJobManager.addSecondarySession(configuration: secondarySessionConfig)
    director.injected[URLSessionJobManager.self] = directorURLSessionJobManager


    assistant = try JobDirector(id: directorID,
                                directory: FileManager.default.temporaryDirectory,
                                mode: .assistant(name: "test"),
                                typeResolver: typeResolver)

    let assistantURLSessionJobManager = URLSessionJobManager(director: assistant,
                                                             primaryConfiguration: secondarySessionConfig)
    assistant.injected[URLSessionJobManager.self] = assistantURLSessionJobManager


    try await director.start()
    try await assistant.start()

    let startedEx = expectation(forNotification: .init("test_UploadJobTransferred.upload.started"), object: nil)

    let progressedEx = expectation(forNotification: .init("test_UploadJobTransferred.main.progressed"), object: nil)
    progressedEx.assertForOverFulfill = false

    let executedEx = expectation(forNotification: .init("test_UploadJobTransferred.main.executed"), object: nil) { not in
      guard let response = not.userInfo?["response"] as? URLSessionJobResponse else {
        return false
      }
      return response.statusCode == 200
    }

    try await assistant.submit(MainJob(fromFile: fileURL, toURL: requestURL))

    await fulfillment(of: [startedEx, progressedEx, executedEx], timeout: 3)
  }

}
