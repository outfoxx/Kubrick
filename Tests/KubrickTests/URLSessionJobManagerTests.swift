//
//  URLSessionJobManagerTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation
import Kubrick
import PotentCodables
import Sunday
import SundayServer
import XCTest


class URLSessionJobManagerTests: XCTestCase {

  var director: JobDirector!

  override func tearDown() async throws {
    if let director {
      try await director.stop()
      self.director = nil
    }
  }

  func test_DownloadJob() async throws {

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
            .onProgress(Self.onProgress)
        }
      }

      static func onProgress(progressedBytes: Int, transferredBytes: Int, totalBytes: Int) {
        NotificationCenter.default.post(name: .init("test_DownloadJob.main.progressed"),
                                        object: nil,
                                        userInfo: [
                                          "progressed": progressedBytes,
                                          "transferred": transferredBytes,
                                          "total": totalBytes
                                        ])
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_DownloadJob.main.executed"),
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

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let progressedEx = expectation(forNotification: .init("test_DownloadJob.main.progressed"), object: nil)
    progressedEx.expectedFulfillmentCount = 3
    progressedEx.assertForOverFulfill = false

    let executedEx = expectation(forNotification: .init("test_DownloadJob.main.executed"), object: nil) { not in
      guard
        let download = not.userInfo?["download"] as? URLSessionDownloadJobResult,
        let fileSize = try? download.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        fileSize == 1024 * 512
      else {
        return false
      }

      return download.response.statusCode == 200 && download.response.url == requestURL
    }

    try await director.submit(MainJob(url: requestURL))

    await fulfillment(of: [progressedEx, executedEx], timeout: 3)
  }

  func test_DownloadJobReportsInvalidResponses() async throws {

    let testServer = try RoutingHTTPServer {
      Path("/test-file") {
        GET { _, response in
          response.send(status: .internalServerError)
        }
      }
    }

    guard let serverURL = testServer.startLocal(timeout: 1) else {
      return XCTFail("Unable to start server")
    }

    struct MainJob: SubmittableJob {
      @JobInput var url: URL
      @JobInput var download: Result<URLSessionDownloadJobResult, Error>

      init(url: URL) {
        self.url = url
        self.$download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .mapToResult()
        }
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_DownloadJobReportsInvalidResponses.main.executed"),
                                        object: nil,
                                        userInfo: [
                                          "result": download
                                        ])
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

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let executed = expectation(forNotification: .init("test_DownloadJobReportsInvalidResponses.main.executed"),
                               object: nil) { not in

      guard
        let result = not.userInfo?["result"] as? Result<URLSessionDownloadJobResult, Error>,
        case .failure(let error) = result
      else {
        return false
      }

      return (error as NSError) == URLSessionJobError.invalidResponseStatus as NSError
    }

    try await director.submit(MainJob(url: requestURL))

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_DownloadJobHandlesError() async throws {

    struct MainJob: SubmittableJob {
      @JobInput var url: URL
      @JobInput var download: Result<URLSessionDownloadJobResult, Error>

      init(url: URL) {
        self.url = url
        self.$download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .mapToResult()
        }
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_DownloadJobHandlesError.main.executed"),
                                        object: nil,
                                        userInfo: [
                                          "result": download
                                        ])
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

    let nonExistentServerURL = URL(string: "http://\(UniqueID.generateString())")!

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let executed = expectation(forNotification: .init("test_DownloadJobHandlesError.main.executed"),
                               object: nil) { not in

      guard
        let result = not.userInfo?["result"] as? Result<URLSessionDownloadJobResult, Error>,
        case .failure(let error) = result
      else {
        return false
      }

      let nsError = error as NSError
      return nsError.domain == URLError.errorDomain && nsError.code == URLError.Code.cannotFindHost.rawValue
    }

    try await director.submit(MainJob(url: nonExistentServerURL))

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_UploadJob() async throws {

    let testServer = try RoutingHTTPServer {
      Path("/test-file") {
        PUT { request, response in
          XCTAssertEqual(request.body?.count, 512 * 1024)
          response.send(status: .ok)
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
            .onProgress(Self.onProgress)
        }
      }

      static func onProgress(progressedBytes: Int, transferredBytes: Int, totalBytes: Int) {
        NotificationCenter.default.post(name: .init("test_UploadJob.main.progressed"),
                                        object: nil,
                                        userInfo: [
                                          "progressed": progressedBytes,
                                          "transferred": transferredBytes,
                                          "total": totalBytes
                                        ])
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_UploadJob.main.executed"),
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

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let progressed = expectation(forNotification: .init("test_UploadJob.main.progressed"), object: nil)
    progressed.assertForOverFulfill = false

    let executed = expectation(forNotification: .init("test_UploadJob.main.executed"), object: nil) { not in
      guard let response = not.userInfo?["response"] as? URLSessionJobResponse else {
        return false
      }
      return response.statusCode == 200
    }

    try await director.submit(MainJob(fromFile: fileURL, toURL: requestURL))

    await fulfillment(of: [progressed, executed], timeout: 3)
  }

  func test_UploadJobReportsInvalidResponses() async throws {

    let testServer = try RoutingHTTPServer {
      Path("/test-file") {
        PUT { request, response in
          response.send(status: .internalServerError)
        }
      }
    }

    guard let serverURL = testServer.startLocal(timeout: 1) else {
      return XCTFail("Unable to start server")
    }

    struct MainJob: SubmittableJob {
      @JobInput var fromFile: URL
      @JobInput var toURL: URL
      @JobInput var response: Result<URLSessionJobResponse, Error>

      init(fromFile: URL, toURL: URL) {
        self.fromFile = fromFile
        self.toURL = toURL
        self.$response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: toURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .mapToResult()
        }
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_UploadJobReportsInvalidResponses.main.executed"),
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

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let executed = expectation(forNotification: .init("test_UploadJobReportsInvalidResponses.main.executed"),
                               object: nil) { not in

      guard
        let result = not.userInfo?["response"] as? Result<URLSessionJobResponse, Error>,
        case .failure(let error) = result
      else {
        return false
      }

      return (error as NSError) == URLSessionJobError.invalidResponseStatus as NSError
    }

    try await director.submit(MainJob(fromFile: fileURL, toURL: requestURL))

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_UploadJobHandlesError() async throws {

    struct MainJob: SubmittableJob {
      @JobInput var fromFile: URL
      @JobInput var toURL: URL
      @JobInput var response: Result<URLSessionJobResponse, Error>

      init(fromFile: URL, toURL: URL) {
        self.fromFile = fromFile
        self.toURL = toURL
        self.$response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: toURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .mapToResult()
        }
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_UploadJobHandlesError.main.executed"),
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

    let nonExistentServerURL = URL(string: "http://\(UniqueID.generateString())")!
    let nonExistentFileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("data")

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default)

    try await director.start()

    let executed = expectation(forNotification: .init("test_UploadJobHandlesError.main.executed"),
                               object: nil) { not in

      guard
        let result = not.userInfo?["response"] as? Result<URLSessionJobResponse, Error>,
        case .failure(let error) = result
      else {
        return false
      }

      let nsError = error as NSError
      return nsError.domain == URLError.errorDomain && nsError.code == URLError.Code.cannotFindHost.rawValue
    }

    try await director.submit(MainJob(fromFile: nonExistentFileURL, toURL: nonExistentServerURL))

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_CustomDelegate() async throws {

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

    class CustomDelegate: URLSessionJobManagerDelegate {

      public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        NotificationCenter.default.post(name: .init("test_CustomDelegate.delegate.started"), object: nil)
      }

    }

    struct MainJob: SubmittableJob {
      @JobInput var url: URL
      @JobInput var download: URLSessionDownloadJobResult

      init(url: URL) {
        self.url = url
        self.$download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .onProgress(Self.onProgress)
        }
      }

      static func onProgress(progressedBytes: Int, transferredBytes: Int, totalBytes: Int) {
        NotificationCenter.default.post(name: .init("test_CustomDelegate.main.progressed"),
                                        object: nil,
                                        userInfo: [
                                          "progressed": progressedBytes,
                                          "transferred": transferredBytes,
                                          "total": totalBytes
                                        ])
      }

      func execute() async {
        NotificationCenter.default.post(name: .init("test_CustomDelegate.main.executed"),
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

    director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(director: director,
                                                                        primaryConfiguration: .default,
                                                                        primaryDelegate: CustomDelegate())

    try await director.start()

    let startedEx = expectation(forNotification: .init("test_CustomDelegate.delegate.started"), object: nil)

    let progressedEx = expectation(forNotification: .init("test_CustomDelegate.main.progressed"), object: nil)
    progressedEx.expectedFulfillmentCount = 3
    progressedEx.assertForOverFulfill = false

    let executedEx = expectation(forNotification: .init("test_CustomDelegate.main.executed"), object: nil) { not in
      guard
        let download = not.userInfo?["download"] as? URLSessionDownloadJobResult,
        let fileSize = try? download.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        fileSize == 1024 * 512
      else {
        return false
      }

      return download.response.statusCode == 200 && download.response.url == requestURL
    }

    try await director.submit(MainJob(url: requestURL))

    await fulfillment(of: [startedEx, progressedEx, executedEx], timeout: 3)
  }

}
