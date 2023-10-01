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
@testable import Kubrick
import Sunday
import SundayServer
import XCTest


class URLSessionJobManagerTests: XCTestCase {

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
      @JobInput var download: URLSessionDownloadJobResult

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onProgress: (Int, Int, Int) -> Void
      let onExecute: (URLSessionDownloadJobResult) -> Void

      init(
        url: URL,
        onProgress: @escaping (Int, Int, Int) -> Void,
        onExecute: @escaping (URLSessionDownloadJobResult) -> Void
      ) {
        self.onProgress = onProgress
        self.onExecute = onExecute
        $download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .progress(progress: onProgress)
        }
      }

      func execute() async {
        onExecute(download)
      }

      init(from: Data, using: any JobDecoder) throws {
        onProgress = { _, _, _ in }
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let requestURL = serverURL.appendingPathComponent("test-file")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let progressed = expectation(description: "Download progressed")
    progressed.assertForOverFulfill = false
    progressed.expectedFulfillmentCount = 2

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(url: requestURL) { _, current, total in
      //print("Progressed: current=\(current), total=\(total)")
      progressed.fulfill()

    } onExecute: { download in

      XCTAssertEqual(try? download.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, 1024 * 512)
      XCTAssertEqual(download.response.url, serverURL.appendingPathComponent("test-file"))
      XCTAssertEqual(download.response.statusCode, 200)
      XCTAssertEqual(download.response.header(forName: HTTP.StdHeaders.contentType), MediaType.octetStream.value)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

    await fulfillment(of: [progressed, executed], timeout: 3)
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
      @JobInput var download: Result<URLSessionDownloadJobResult, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<URLSessionDownloadJobResult, Error>) -> Void

      init(
        url: URL,
        onExecute: @escaping (Result<URLSessionDownloadJobResult, Error>) -> Void
      ) {
        self.onExecute = onExecute
        $download.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(download)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let requestURL = serverURL.appendingPathComponent("test-file")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(url: requestURL) { result in

      guard case .failure(let error) = result else {
        return XCTFail("Upload should have failed")
      }

      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, (URLSessionJobError.invalidResponseStatus as NSError).domain)
      XCTAssertEqual(nsError.code, (URLSessionJobError.invalidResponseStatus as NSError).code)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_DownloadJobHandlesError() async throws {

    struct MainJob: SubmittableJob {
      @JobInput var response: Result<URLSessionDownloadJobResult, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<URLSessionDownloadJobResult, Error>) -> Void

      init(url: URL, onExecute: @escaping (Result<URLSessionDownloadJobResult, Error>) -> Void) {
        self.onExecute = onExecute
        $response.bind {
          URLSessionDownloadFileJob()
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(response)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let nonExistentServerURL = URL(string: "http://\(UniqueID.generateString())")!

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(url: nonExistentServerURL) { result in

      guard case .failure(let error) = result else {
        return XCTFail("Upload should have failed")
      }

      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, URLError.errorDomain)
      XCTAssertEqual(nsError.code, URLError.Code.cannotFindHost.rawValue)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

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
      @JobInput var response: URLSessionJobResponse

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onProgress: (Int, Int, Int) -> Void
      let onExecute: (URLSessionJobResponse) -> Void

      init(
        fromFile: URL,
        toURL url: URL,
        onProgress: @escaping (Int, Int, Int) -> Void,
        onExecute: @escaping (URLSessionJobResponse) -> Void
      ) {
        self.onProgress = onProgress
        self.onExecute = onExecute
        $response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .progress(progress: onProgress)
        }
      }

      func execute() async {
        onExecute(response)
      }

      init(from: Data, using: any JobDecoder) throws {
        onProgress = { _, _, _ in }
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
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

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let progressed = expectation(description: "Upload progressed")
    progressed.assertForOverFulfill = false

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(fromFile: fileURL, toURL: requestURL) { _, current, total in
      //print("Progressed: current=\(current), total=\(total)")
      progressed.fulfill()

    } onExecute: { response in

      XCTAssertEqual(response.statusCode, 200)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

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
      @JobInput var response: Result<URLSessionJobResponse, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<URLSessionJobResponse, Error>) -> Void

      init(
        fromFile: URL,
        toURL url: URL,
        onExecute: @escaping (Result<URLSessionJobResponse, Error>) -> Void
      ) {
        self.onExecute = onExecute
        $response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(response)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
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

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(fromFile: fileURL, toURL: requestURL) { result in

      guard case .failure(let error) = result else {
        return XCTFail("Upload should have failed")
      }

      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, (URLSessionJobError.invalidResponseStatus as NSError).domain)
      XCTAssertEqual(nsError.code, (URLSessionJobError.invalidResponseStatus as NSError).code)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

    await fulfillment(of: [executed], timeout: 3)
  }

  func test_UploadJobHandlesError() async throws {

    struct MainJob: SubmittableJob {
      @JobInput var response: Result<URLSessionJobResponse, Error>

      // TESTING: DO NOT DO THIS IN SUBMITTABLE JOB
      let onExecute: (Result<URLSessionJobResponse, Error>) -> Void

      init(
        fromFile: URL,
        toURL url: URL,
        onExecute: @escaping (Result<URLSessionJobResponse, Error>) -> Void
      ) {
        self.onExecute = onExecute
        $response.bind {
          URLSessionUploadFileJob()
            .fromFile(fromFile)
            .request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData).with(httpMethod: .put))
            .mapToResult()
        }
      }

      func execute() async {
        onExecute(response)
      }

      init(from: Data, using: any JobDecoder) throws {
        onExecute = { _ in }
      }
      func encode(using: any JobEncoder) throws -> Data { Data() }
    }

    let typeResolver = TypeNameTypeResolver(jobs: [
      MainJob.self
    ])

    let nonExistentServerURL = URL(string: "http://\(UniqueID.generateString())")!
    let nonExistentFileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UniqueID.generateString())
      .appendingPathExtension("data")

    let director = try JobDirector(directory: FileManager.default.temporaryDirectory, typeResolver: typeResolver)
    director.injected[URLSessionJobManager.self] = URLSessionJobManager(configuration: .default, director: director)

    try await director.start()

    let executed = expectation(description: "MainJob executed")

    let id = JobID()
    let mainJob = MainJob(fromFile: nonExistentFileURL, toURL: nonExistentServerURL) { result in

      guard case .failure(let error) = result else {
        return XCTFail("Upload should have failed")
      }

      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, URLError.errorDomain)
      XCTAssertEqual(nsError.code, URLError.Code.cannotFindHost.rawValue)

      executed.fulfill()
    }

    try await director.submit(mainJob, as: id)

    await fulfillment(of: [executed], timeout: 3)
  }

}
