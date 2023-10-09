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


public enum URLSessionJobManagerError: JobError {
  case invalidResponse
  case downloadedFileMissing
}


public actor URLSessionJobManager {

  public typealias OnStart = (_ director: JobDirector, _ task: URLSessionTask) async throws -> Void
  public typealias OnProgress = (_ progressedBytes: Int, _ transferredBytes: Int, _ totalBytes: Int) async -> Void

  public class Delegate: NSObject, URLSessionDownloadDelegate {

    weak var owner: URLSessionJobManager?

    init(owner: URLSessionJobManager? = nil) {
      self.owner = owner
    }

    func queueTask(session: URLSession, operation: @Sendable @escaping () async throws -> Void) {
      session.delegateQueue.addOperation(TaskOperation(operation: operation))
    }

    public func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didSendBodyData bytesSent: Int64,
      totalBytesSent: Int64,
      totalBytesExpectedToSend: Int64
    ) {
      guard let owner else { return }

      logger.debug("[\(task.taskIdentifier)] Upload progress update")

      queueTask(session: session) {
        guard let (jobKey, taskJobInfo) = try await owner.findTaskJobInfo(task: task) else {
          logger.jobTrace {
            $0.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          }
          return
        }

        logger.jobTrace { $0.debug("[\(task.taskIdentifier)] Reporting progress to job handler") }

        await owner.director.runAs(jobKey: jobKey) {
          await taskJobInfo.onProgress?(Int(bytesSent), Int(totalBytesSent), Int(totalBytesExpectedToSend))
        }
      }
    }

    public func urlSession(
      _ session: URLSession,
      downloadTask task: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      guard let owner else { return }

      logger.debug("[\(task.taskIdentifier)] Download progress update")

      queueTask(session: session) {
        guard let (jobKey, taskJobInfo) = try await owner.findTaskJobInfo(task: task) else {
          logger.jobTrace {
            $0.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          }
          return
        }

        logger.jobTrace { $0.debug("[\(task.taskIdentifier)] Reporting progress to job handler") }

        await owner.director.runAs(jobKey: jobKey) {
          await taskJobInfo.onProgress?(Int(bytesWritten), Int(totalBytesWritten), Int(totalBytesExpectedToWrite))
        }
      }
    }

    public func urlSession(
      _ session: URLSession,
      downloadTask task: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      guard let owner else { return }

      logger.debug("[\(task.taskIdentifier)] Download finished")

      let result: Result<URL, Error>
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
        logger.error(
          """
          [\(task.taskIdentifier)] Failed to move downlaoded file to temporary location: \
          erorr=\(error, privacy: .public)
          """
        )
        result = .failure(error)
      }

      queueTask(session: session) {
        guard let (_, taskJobInfo) = try await owner.findTaskJobInfo(task: task) else {
          logger.jobTrace {
            $0.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          }
          return
        }

        guard let downloadTaskJobInfo = taskJobInfo as? DownloadTaskJobInfo else {
          logger.error("[\(task.taskIdentifier)] Invalid info for download task")
          return
        }

        do {
          logger.jobTrace { $0.trace("[\(task.taskIdentifier)] Reporting url to job") }

          await downloadTaskJobInfo.save(url: try result.get())
        }
        catch {
          logger.jobTrace { $0.trace("[\(task.taskIdentifier)] Reporting copy failure to job") }

          await downloadTaskJobInfo.future.fulfill(throwing: error)
        }
      }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
      guard let owner else { return }

      if let error {
        logger.error("[\(task.taskIdentifier)] Task failed: error=\(error, privacy: .public)")
      }
      else {
        logger.debug("[\(task.taskIdentifier)] Task completed successfully")
      }

      queueTask(session: session) {
        guard let (_, taskJobInfo) = try await owner.findTaskJobInfo(task: task) else {
          logger.jobTrace {
            $0.trace("[\(task.taskIdentifier)] Unrelated task: task-description=\(task.taskDescription ?? "")")
          }
          return
        }

        logger.jobTrace { $0.trace("[\(task.taskIdentifier)] Fulfilling job") }

        await taskJobInfo.finish(response: task.response as? HTTPURLResponse, error: error)
      }
    }

  }

  actor DownloadTaskJobInfo: URLSessionTaskJobInfo {

    typealias Result = (fileURL: URL, response: URLSessionJobResponse)

    let task: URLSessionTask
    let onProgress: OnProgress?
    let future: Future<Result, Error>
    var url: URL?

    init(task: URLSessionTask, future: Future<Result, Error>, onProgress: OnProgress?) {
      self.task = task
      self.future = future
      self.onProgress = onProgress
    }

    func save(url: URL) {
      self.url = url
    }

    func finish(response: URLResponse?, error: Error?) async {

      if let error {
        return await future.fulfill(throwing: error)
      }

      guard let url else {
        return await future.fulfill(throwing: URLSessionJobManagerError.downloadedFileMissing)
      }

      guard
        let httpResponse = response as? HTTPURLResponse,
        let httpURL = httpResponse.url
      else {
        return await future.fulfill(throwing: URLSessionJobManagerError.invalidResponse)
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
    let onProgress: OnProgress?
    let future: Future<URLSessionJobResponse, Error>

    init(task: URLSessionTask, future: Future<URLSessionJobResponse, Error>, onProgress: OnProgress?) {
      self.task = task
      self.onProgress = onProgress
      self.future = future
    }

    func finish(response: URLResponse?, error: Error?) async {

      if let error {
        await future.fulfill(throwing: error)
        return
      }

      guard 
        let httpResponse = response as? HTTPURLResponse,
        let httpURL = httpResponse.url
      else {
        await future.fulfill(throwing: URLSessionJobManagerError.invalidResponse)
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

  private let director: JobDirector
  private let primarySession: URLSession
  private var secondardarySessions: [URLSession] = []
  private let sessionDelegatesQueue: OperationQueue
  private let taskJobInfoCache = RegisterCache<JobKey, URLSessionTaskJobInfo>()

  public init(director: JobDirector, primaryConfiguration: URLSessionConfiguration) {
    self.director = director
    self.sessionDelegatesQueue = OperationQueue()
    self.sessionDelegatesQueue.maxConcurrentOperationCount = 1
    self.sessionDelegatesQueue.isSuspended = true

    let delegate = Delegate()
    self.primarySession = URLSession(configuration: primaryConfiguration,
                                     delegate: delegate,
                                     delegateQueue: sessionDelegatesQueue)
    delegate.owner = self

    self.sessionDelegatesQueue.isSuspended = false
  }

  public func addSecondarySession(configuration: URLSessionConfiguration) {
    let delegate = Delegate(owner: self)
    let urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: sessionDelegatesQueue)
    secondardarySessions.append(urlSession)
  }

  func download(
    request: URLRequest,
    onStart: OnStart?,
    onProgress: OnProgress?
  ) async throws -> DownloadTaskJobInfo.Result {

    guard let jobKey = JobDirector.currentJobKey else {
      fatalError("No current job key")
    }

    logger.jobTrace { $0.trace("[\(jobKey)] Registering download: request=\(request)") }

    let taskJobInfo = try await taskJobInfoCache.register(for: jobKey) {

      let downloadTask: URLSessionDownloadTask
      if
        let (existingTask, existingSession) = await self.findJobTask(jobKey: jobKey),
        let existingDownloadTask = existingTask as? URLSessionDownloadTask
      {
        logger.debug(
          """
          [\(jobKey)] Found existing download task: \
          task-id=\(existingDownloadTask.taskIdentifier), \
          session-id=\(existingSession.configuration.identifier ?? "nil", privacy: .public)
          """
        )
        downloadTask = existingDownloadTask
      }
      else {
        logger.info("[\(jobKey)] Starting download task")
        downloadTask = self.primarySession.downloadTask(with: request)
        downloadTask.taskDescription = ExternalJobKey(directorId: self.director.id, jobKey: jobKey).value
        downloadTask.resume()

        try await onStart?(self.director, downloadTask)
      }

      return DownloadTaskJobInfo(task: downloadTask, future: .init(), onProgress: onProgress)

    } as! DownloadTaskJobInfo

    logger.jobTrace { $0.debug("[\(jobKey)] Waiting on download") }

    if let error = taskJobInfo.task.error {
      await taskJobInfo.finish(response: nil, error: error)
    }

    return try await withTaskCancellationHandler {
      try await taskJobInfo.future.get()
    } onCancel: {
      Task { try await cancel(jobKey: jobKey) }
    }
  }

  public func upload(
    fromFile file: URL,
    request: URLRequest,
    onStart: OnStart?,
    onProgress: OnProgress?
  ) async throws -> URLSessionJobResponse {

    guard let jobKey = JobDirector.currentJobKey else {
      fatalError("No current job key")
    }

    logger.jobTrace { $0.trace("[\(jobKey)] Registering upload: request=\(request)") }

    let taskJobInfo = try await taskJobInfoCache.register(for: jobKey) {

      let uploadTask: URLSessionUploadTask
      if
        let (existingTask, existingSession) = await self.findJobTask(jobKey: jobKey),
        let existingUploadTask = existingTask as? URLSessionUploadTask
      {
        logger.debug(
          """
          [\(jobKey)] Found existing upload task: \
          task-id=\(existingUploadTask.taskIdentifier), \
          session-id=\(existingSession.configuration.identifier ?? "nil", privacy: .public)
          """
        )
        uploadTask = existingUploadTask
      }
      else {
        logger.info("[\(jobKey)] Starting upload task")
        uploadTask = self.primarySession.uploadTask(with: request, fromFile: file)
        uploadTask.taskDescription = ExternalJobKey(directorId: self.director.id, jobKey: jobKey).value
        uploadTask.resume()

        try await onStart?(self.director, uploadTask)
      }

      return UploadTaskJobInfo(task: uploadTask, future: .init(), onProgress: onProgress)

    } as! UploadTaskJobInfo

    logger.jobTrace { $0.debug("[\(jobKey)] Waiting on upload") }

    if let error = taskJobInfo.task.error {
      await taskJobInfo.finish(response: nil, error: error)
    }

    return try await withTaskCancellationHandler {
      try await taskJobInfo.future.get()
    } onCancel: {
      Task { try await cancel(jobKey: jobKey) }
    }
  }

  func findTaskJobInfo(task: URLSessionTask) async throws -> (JobKey, URLSessionTaskJobInfo)? {
    guard
      let taskDescription = task.taskDescription,
      let externalJobKey = ExternalJobKey(string: taskDescription),
      externalJobKey.directorId == director.id
    else {
      return nil
    }
    return (externalJobKey.jobKey, try await taskJobInfoCache.valueWhenAvailable(for: externalJobKey.jobKey))
  }

  func findJobTask(jobKey: JobKey) async -> (URLSessionTask, URLSession)? {
    let externalJobKey = ExternalJobKey(directorId: director.id, jobKey: jobKey)
    
    func find(in session: URLSession) async -> URLSessionTask? {
      let tasks = await session.allTasks
      for task in tasks {
        if task.taskDescription == externalJobKey.value {
          return task
        }
      }
      return nil
    }

    let allSessions = [primarySession] + secondardarySessions
    for session in allSessions {
      if let task = await find(in: session) {
        return (task, session)
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
  var onProgress: URLSessionJobManager.OnProgress? { get }

  func finish(response: URLResponse?, error: Error?) async

}


public enum URLSessionJobError: Error {
  case invalidResponseStatus
}


public struct URLSessionJobResponse: Codable, JobHashable {
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


public struct URLSessionDownloadJobResult: Codable, JobHashable {
  public var fileURL: URL
  public var response: URLSessionJobResponse
}


// MARK: Download Job

public struct URLSessionDownloadFileJob: ResultJob {

  public typealias ResultValue = URLSessionDownloadJobResult

  @JobInput public var request: URLRequest
  public var onStart: URLSessionJobManager.OnStart? = nil
  public var onProgress: URLSessionJobManager.OnProgress? = nil

  @JobInject private var manager: URLSessionJobManager

  public init() {}

  public func execute() async throws -> ResultValue {
    
    let (fileURL, response) = try await manager.download(request: request, onStart: onStart, onProgress: onProgress)

    guard (200 ..< 299).contains(response.statusCode) else {
      throw URLSessionJobError.invalidResponseStatus
    }

    return ResultValue(fileURL: fileURL, response: response)
  }

  public func request(_ request: URLRequest) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new.request = request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func request(@JobBuilder<URLRequest> _ jobBuilder: () -> some Job<URLRequest>) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new.$request.bind(job: jobBuilder())
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func onStart(_ onStart: @escaping URLSessionJobManager.OnStart) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func onProgress(_ onProgress: @escaping URLSessionJobManager.OnProgress) -> URLSessionDownloadFileJob {
    var new = URLSessionDownloadFileJob()
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

}


// MARK: Upload Job

public struct URLSessionUploadFileJob: ResultJob {

  @JobInput public var fromFile: URL
  @JobInput public var request: URLRequest
  public var onStart: URLSessionJobManager.OnStart? = nil
  public var onProgress: URLSessionJobManager.OnProgress? = nil

  @JobInject private var manager: URLSessionJobManager

  public init() {}

  public func execute() async throws -> URLSessionJobResponse {

    let response = try await manager.upload(fromFile: fromFile,
                                            request: request,
                                            onStart: onStart,
                                            onProgress: onProgress)

    guard (200 ..< 299).contains(response.statusCode) else {
      throw URLSessionJobError.invalidResponseStatus
    }

    return response
  }

  public func fromFile(_ fromFile: URL) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new.fromFile = fromFile
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func fromFile(@JobBuilder<URL> _ jobBuilder: () -> some Job<URL>) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new.$fromFile.bind(job: jobBuilder())
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func request(_ request: URLRequest) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new.request = request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func request(@JobBuilder<URLRequest> _ jobBuilder: () -> some Job<URLRequest>) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new.$request.bind(job: jobBuilder())
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func onStart(_ onStart: @escaping URLSessionJobManager.OnStart) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

  public func onProgress(_ onProgress: @escaping URLSessionJobManager.OnProgress) -> URLSessionUploadFileJob {
    var new = URLSessionUploadFileJob()
    new._fromFile = _fromFile
    new._request = _request
    new.onStart = onStart
    new.onProgress = onProgress
    return new
  }

}


extension URLRequest: Codable, JobHashable {

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
    if #available(macOS 13, iOS 16.1, tvOS 16, watchOS 8, *) {
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
    if #available(macOS 13, iOS 16.1, tvOS 16, watchOS 8, *) {
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
