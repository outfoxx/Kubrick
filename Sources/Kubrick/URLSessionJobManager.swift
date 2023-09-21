//
//  URLSessionJobManager.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation
import OSLog
import RegexBuilder


private let logger = Logger.for(category: "URLSessionJobs")


public actor URLSessionJobManager {

  public enum Error: String, Swift.Error {
    case invalidResponse
    case downloadedFileMissing
  }

  public typealias Progress = (_ chunkBytes: Int, _ currentBytes: Int, _ totalBytes: Int) async throws -> Void

  public class Delegate: NSObject, URLSessionDownloadDelegate {

    weak var owner: URLSessionJobManager?

    func queueTask(operation: @Sendable @escaping () async throws -> Void) {
      owner?.urlSession.delegateQueue.addOperation(TaskOperation(operation: operation))
    }

    public func urlSession(
      _ session: URLSession,
      downloadTask task: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      guard let owner else { return }

      logger.trace("[\(task.taskIdentifier)] Download progress update")

      queueTask {
        guard let taskJobInfo = try await owner.findTaskJobInfo(task: task) else {
          logger.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          return
        }

        logger.debug("[\(task.taskIdentifier)] Reporting progress to job handler")

        try await taskJobInfo.progress?(Int(bytesWritten), Int(totalBytesWritten), Int(totalBytesExpectedToWrite))
      }
    }

    public func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didSendBodyData bytesSent: Int64,
      totalBytesSent: Int64,
      totalBytesExpectedToSend: Int64
    ) {
      guard let owner else { return }

      logger.trace("[\(task.taskIdentifier)] Upload progress update")

      queueTask {
        guard let taskJobInfo = try await owner.findTaskJobInfo(task: task) else {
          logger.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          return
        }

        logger.debug("[\(task.taskIdentifier)] Reporting progress to job handler")

        try await taskJobInfo.progress?(Int(bytesSent), Int(totalBytesSent), Int(totalBytesExpectedToSend))
      }
    }

    public func urlSession(
      _ session: URLSession,
      downloadTask task: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      guard let owner else { return }

      logger.trace("[\(task.taskIdentifier)] Download finished")

      let result: Result<URL, Swift.Error>
      do {
        let temporaryDir = try FileManager.default.url(for: .itemReplacementDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: location, create: true)

        let targetFile = temporaryDir
          .appendingPathComponent(UniqueID.generateString())
          .appendingPathExtension("download")

        try FileManager.default.copyItem(at: location, to: targetFile)

        result = .success(targetFile)
      }
      catch {
        logger.error("[\(task.taskIdentifier)] Failed to move downlaoded file to temporary location: erorr=\(error, privacy: .public)")
        result = .failure(error)
      }

      queueTask {
        guard let taskJobInfo = try await owner.findTaskJobInfo(task: task) else {
          logger.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          return
        }

        guard let downloadTaskJobInfo = taskJobInfo as? DownloadTaskJobInfo else {
          logger.error("[\(task.taskIdentifier)] Invalid info for download task")
          return
        }

        do {
          logger.trace("[\(task.taskIdentifier)] Reporting url to job")

          await downloadTaskJobInfo.save(url: try result.get())
        }
        catch {
          logger.trace("[\(task.taskIdentifier)] Reporting copy failure to job")

          await downloadTaskJobInfo.future.fulfill(throwing: error)
        }
      }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
      guard let owner else { return }

      if let error {
        logger.error("[\(task.taskIdentifier)] Task failed: error=\(error, privacy: .public)")
      }
      else {
        logger.trace("[\(task.taskIdentifier)] Task completed successfully")
      }

      queueTask {
        guard let taskJobInfo = try await owner.findTaskJobInfo(task: task) else {
          logger.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          return
        }

        logger.trace("[\(task.taskIdentifier)] Fulfilling job")

        await taskJobInfo.finish(response: task.response as? HTTPURLResponse, error: error)
      }
    }

  }

  actor DownloadTaskJobInfo: URLSessionTaskJobInfo {

    typealias Result = (fileURL: URL, response: URLSessionJobResponse)

    let task: URLSessionTask
    let progress: Progress?
    let future: Future<Result, Swift.Error>
    var url: URL?

    init(task: URLSessionTask, future: Future<Result, Swift.Error>, progress: Progress?) {
      self.task = task
      self.future = future
      self.progress = progress
    }

    func save(url: URL) {
      self.url = url
    }

    func finish(response: URLResponse?, error: Swift.Error?) async {

      if let error {
        return await future.fulfill(throwing: error)
      }

      guard let url else {
        return await future.fulfill(throwing: Error.downloadedFileMissing)
      }

      guard
        let httpResponse = response as? HTTPURLResponse,
        let httpURL = httpResponse.url
      else {
        return await future.fulfill(throwing: Error.invalidResponse)
      }

      let httpHeaders = httpResponse
        .allHeaderFields
        .map { (key, value) in
          let strings: [String]
          switch value {
          case let value as CustomStringConvertible:
            strings = [value.description]
          case let value as Array<CustomStringConvertible>:
            strings = value.map { $0.description }
          default:
            strings = []
          }
          return (String(describing: key), strings)
        }

      let response = URLSessionJobResponse(url: httpURL,
                                           headers: Dictionary(uniqueKeysWithValues: httpHeaders),
                                           statusCode: httpResponse.statusCode)


      await future.fulfill(producing: (url, response))
    }
  }

  struct UploadTaskJobInfo: URLSessionTaskJobInfo {

    let task: URLSessionTask
    let progress: Progress?
    let future: Future<URLSessionJobResponse, Swift.Error>

    init(task: URLSessionTask, future: Future<URLSessionJobResponse, Swift.Error>, progress: Progress?) {
      self.task = task
      self.progress = progress
      self.future = future
    }

    func finish(response: URLResponse?, error: Swift.Error?) async {

      if let error {
        await future.fulfill(throwing: error)
        return
      }

      guard 
        let httpResponse = response as? HTTPURLResponse,
        let httpURL = httpResponse.url
      else {
        await future.fulfill(throwing: Error.invalidResponse)
        return
      }

      let httpHeaders = httpResponse
        .allHeaderFields
        .map { (key, value) in
          let strings: [String]
          switch value {
          case let value as CustomStringConvertible:
            strings = [value.description]
          case let value as Array<CustomStringConvertible>:
            strings = value.map { $0.description }
          default:
            strings = []
          }
          return (String(describing: key), strings)
        }

      let response = URLSessionJobResponse(url: httpURL,
                                           headers: Dictionary(uniqueKeysWithValues: httpHeaders),
                                           statusCode: httpResponse.statusCode)

      await future.fulfill(producing: response)
    }
  }

  public nonisolated let urlSession: URLSession

  private let director: JobDirector
  private let taskJobInfoCache = RegisterCache<JobKey, URLSessionTaskJobInfo>()

  public init(configuration: URLSessionConfiguration, director: JobDirector) {
    let operationQueue = OperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    operationQueue.isSuspended = true
    
    let delegate = Delegate()

    self.urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: operationQueue)
    self.director = director

    delegate.owner = self
    operationQueue.isSuspended = false
  }

  public func download(request: URLRequest, progress: Progress?) async throws -> (URL, URLSessionJobResponse) {
    guard let jobKey = JobDirector.currentJobKey else {
      fatalError("No current job key")
    }

    logger.trace("[\(jobKey)] Registering download: request=\(request)")

    let taskJobInfo = try await taskJobInfoCache.register(for: jobKey) {

      let downloadTask: URLSessionDownloadTask
      if
        let existingTask = await self.findJobTask(jobKey: jobKey),
        let existingDownloadTask = existingTask as? URLSessionDownloadTask
      {
        logger.debug("[\(jobKey)] Found existing download task: task-id=\(existingDownloadTask.taskIdentifier)")
        downloadTask = existingDownloadTask
      }
      else {
        logger.info("[\(jobKey)] Starting download task")
        downloadTask = self.urlSession.downloadTask(with: request)
        downloadTask.taskDescription = taskJobId(directorId: self.director.id, jobKey: jobKey)
        downloadTask.resume()
      }

      return DownloadTaskJobInfo(task: downloadTask, future: .init(), progress: progress)

    } as! DownloadTaskJobInfo

    logger.debug("[\(jobKey)] Waiting on download")

    return try await withTaskCancellationHandler {
      try await taskJobInfo.future.get()
    } onCancel: {
      Task { try await cancel(jobKey: jobKey) }
    }
  }

  public func upload(
    fromFile file: URL,
    request: URLRequest,
    progress: Progress?
  ) async throws -> URLSessionJobResponse {

    guard let jobKey = JobDirector.currentJobKey else {
      fatalError("No current job key")
    }

    logger.trace("[\(jobKey)] Registering upload: request=\(request)")

    let taskJobInfo = try await taskJobInfoCache.register(for: jobKey) {

      let uploadTask: URLSessionUploadTask
      if
        let existingTask = await self.findJobTask(jobKey: jobKey),
        let existingUploadTask = existingTask as? URLSessionUploadTask
      {
        logger.debug("[\(jobKey)] Found existing upload task: task-id=\(existingUploadTask.taskIdentifier)")
        uploadTask = existingUploadTask
      }
      else {
        logger.info("[\(jobKey)] Starting upload task")
        uploadTask = self.urlSession.uploadTask(with: request, fromFile: file)
        uploadTask.taskDescription = taskJobId(directorId: self.director.id, jobKey: jobKey)
        uploadTask.resume()
      }

      return UploadTaskJobInfo(task: uploadTask, future: .init(), progress: progress)

    } as! UploadTaskJobInfo

    logger.debug("[\(jobKey)] Waiting on upload")

    return try await withTaskCancellationHandler {
      try await taskJobInfo.future.get()
    } onCancel: {
      Task { try await cancel(jobKey: jobKey) }
    }
  }

  func findTaskJobInfo(task: URLSessionTask) async throws -> URLSessionTaskJobInfo? {
    guard
      let taskDescription = task.taskDescription,
      let (directorId, jobKey) = try parseTaskJobId(string: taskDescription),
      directorId == director.id
    else {
      return nil
    }
    return try await taskJobInfoCache.valueWhenAvailable(for: jobKey)
  }

  func findJobTask(jobKey: JobKey) async -> URLSessionTask? {
    let tasks = await urlSession.allTasks
    let taskJobId = taskJobId(directorId: director.id, jobKey: jobKey)
    for task in tasks {
      if task.taskDescription == taskJobId {
        return task
      }
    }
    return nil
  }

  func cancel(jobKey: JobKey) async throws {

    logger.info("[\(jobKey)] Cancelling task")

    try await taskJobInfoCache.valueIfRegistered(for: jobKey)?.task.cancel()
  }

}


protocol URLSessionTaskJobInfo {

  var task: URLSessionTask { get }
  var progress: URLSessionJobManager.Progress? { get }

  func finish(response: URLResponse?, error: Error?) async

}


public enum URLSessionJobError: Error {
  case invalidResponseStatus
}


public struct URLSessionJobResponse: Codable {
  var url: URL
  var headers: [String: [String]]
  var statusCode: Int

  func header(forName name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.first
  }

  func headers(forName name: String) -> [String] {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? []
  }

}


public struct URLSessionDownloadJobResult: Codable {
  var fileURL: URL
  var response: URLSessionJobResponse
}


// MARK: Download Job

public struct URLSessionDownloadFileJob: ResultJob {

  public typealias ResultValue = URLSessionDownloadJobResult

  @JobInput public var request: URLRequest
  public var progress: URLSessionJobManager.Progress? = nil

  @JobInject private var manager: URLSessionJobManager

  public init() {}

  public func execute() async throws -> ResultValue {
    
    let (fileURL, response) = try await manager.download(request: request, progress: progress)

    guard (200 ..< 299).contains(response.statusCode) else {
      throw URLSessionJobError.invalidResponseStatus
    }

    return ResultValue(fileURL: fileURL, response: response)
  }

  public func request(_ request: URLRequest) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new.request = request
    new.progress = progress
    return new
  }

  public func request(@JobBuilder<URLRequest> _ jobBuilder: () -> some Job<URLRequest>) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new.$request.bind(job: jobBuilder())
    new.progress = progress
    return new
  }

  public func progress(progress: @escaping URLSessionJobManager.Progress) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new._request = _request
    new.progress = progress
    return new
  }

}


// MARK: Upload Job

public struct URLSessionUploadFileJob: ResultJob {

  @JobInput public var fromFile: URL
  @JobInput public var request: URLRequest
  public var progress: URLSessionJobManager.Progress? = nil

  @JobInject private var manager: URLSessionJobManager

  public init() {}

  public func execute() async throws -> URLSessionJobResponse {

    let response = try await manager.upload(fromFile: fromFile, request: request, progress: progress)

    guard (200 ..< 299).contains(response.statusCode) else {
      throw URLSessionJobError.invalidResponseStatus
    }

    return response
  }

  public func fromFile(_ fromFile: URL) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new.fromFile = fromFile
    new._request = _request
    new.progress = progress
    return new
  }

  public func fromFile(@JobBuilder<URL> _ jobBuilder: () -> some Job<URL>) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new.$fromFile.bind(job: jobBuilder())
    new._request = _request
    new.progress = progress
    return new
  }

  public func request(_ request: URLRequest) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new.request = request
    new.progress = progress
    return new
  }

  public func request(@JobBuilder<URLRequest> _ jobBuilder: () -> some Job<URLRequest>) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new.$request.bind(job: jobBuilder())
    new.progress = progress
    return new
  }

  public func progress(progress: @escaping URLSessionJobManager.Progress) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new._request = _request
    new.progress = progress
    return new
  }

}


extension URLRequest: Codable {

  enum CodingKeys: String, CodingKey {
    case url
    case httpMethod
    case allHTTPHeaderFields
    case httpBody
    case httpShouldHandleCookies
    case httpShouldUsePipelining
    case cachePolicy
    case timeoutInterval
    case mainDocumentURL
    case networkServiceType
    case allowsCellularAccess
    case allowsExpensiveNetworkAccess
    case allowsConstrainedNetworkAccess
    case assumesHTTP3Capable
    case attribution
    case requiresDNSSECValidation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let url = try container.decode(URL.self, forKey: .url)
    let cachePolicy = CachePolicy(rawValue: try container.decode(CachePolicy.RawValue.self, forKey: .cachePolicy)) ?? .useProtocolCachePolicy
    let timeoutInterval = try container.decode(TimeInterval.self, forKey: .timeoutInterval)
    self.init(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    httpMethod = try container.decodeIfPresent(String.self, forKey: .httpMethod)
    allHTTPHeaderFields = try container.decodeIfPresent([String: String].self, forKey: .allHTTPHeaderFields)
    httpBody = try container.decodeIfPresent(Data.self, forKey: .httpBody)
    httpShouldHandleCookies = try container.decode(Bool.self, forKey: .httpShouldHandleCookies)
    httpShouldUsePipelining = try container.decode(Bool.self, forKey: .httpShouldUsePipelining)
    mainDocumentURL = try container.decodeIfPresent(URL.self, forKey: .mainDocumentURL)
    networkServiceType = NetworkServiceType(rawValue: try container.decode(NetworkServiceType.RawValue.self, forKey: .networkServiceType)) ?? .default
    allowsCellularAccess = try container.decode(Bool.self, forKey: .allowsCellularAccess)
    allowsExpensiveNetworkAccess = try container.decode(Bool.self, forKey: .allowsExpensiveNetworkAccess)
    allowsConstrainedNetworkAccess = try container.decode(Bool.self, forKey: .allowsConstrainedNetworkAccess)
    assumesHTTP3Capable = try container.decode(Bool.self, forKey: .assumesHTTP3Capable)
    attribution = Attribution(rawValue: try container.decode(Attribution.RawValue.self, forKey: .attribution)) ?? .developer
    if #available(macOS 13, iOS 16, tvOS 16, watchOS 8, *) {
      requiresDNSSECValidation = try container.decode(Bool.self, forKey: .requiresDNSSECValidation)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(url, forKey: .url)
    try container.encode(cachePolicy.rawValue, forKey: .cachePolicy)
    try container.encode(timeoutInterval, forKey: .timeoutInterval)
    try container.encode(httpMethod, forKey: .httpMethod)
    try container.encode(allHTTPHeaderFields, forKey: .allHTTPHeaderFields)
    try container.encode(httpBody, forKey: .httpBody)
    try container.encode(httpShouldHandleCookies, forKey: .httpShouldHandleCookies)
    try container.encode(httpShouldUsePipelining, forKey: .httpShouldUsePipelining)
    try container.encode(mainDocumentURL, forKey: .mainDocumentURL)
    try container.encode(networkServiceType.rawValue, forKey: .networkServiceType)
    try container.encode(allowsCellularAccess, forKey: .allowsCellularAccess)
    try container.encode(allowsExpensiveNetworkAccess, forKey: .allowsExpensiveNetworkAccess)
    try container.encode(allowsConstrainedNetworkAccess, forKey: .allowsConstrainedNetworkAccess)
    try container.encode(assumesHTTP3Capable, forKey: .assumesHTTP3Capable)
    try container.encode(attribution.rawValue, forKey: .attribution)
    if #available(macOS 13, iOS 16, tvOS 16, watchOS 8, *) {
      try container.encode(requiresDNSSECValidation, forKey: .requiresDNSSECValidation)
    }
  }

}


extension URLSession {

  func findTask(identifier: Int) async -> URLSessionTask? {
    return await allTasks.first { task in
      task.taskIdentifier == identifier
    }
  }

}


func taskJobId(directorId: JobDirector.ID, jobKey: JobKey) -> String {
  return "\(taskJobIdScheme)://\(directorId)#\(jobKey)"
}

func parseTaskJobId(string: String) throws -> (directorId: JobDirector.ID, jobKey: JobKey)? {
  guard
    let result = taskJobIdRegex.matches(string, groupNames: ["directorid", "jobkey"]),
    let directorID = result["directorid"].flatMap({ JobID(string: String($0)) }),
    let jobKey = result["jobkey"].flatMap({ JobKey(string: String($0)) })
  else {
    return nil
  }
  return (directorID, jobKey)
}

private let taskJobIdScheme = "director"
private let taskJobIdRegex = NSRegularExpression(#"\#(taskJobIdScheme)://(?<directorid>[a-zA-Z0-9]+)#(?<jobkey>.*)"#)
