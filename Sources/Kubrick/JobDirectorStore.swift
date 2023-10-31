//
//  JobDirectorStore.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation
import IOStreams
import OSLog
import PotentCBOR
import UniformTypeIdentifiers


private let logger = Logger.for(category: "JobDirectorStore")


class JobDirectorStore: RegisterCacheStore, SubmittableJobStore {

  enum Error: Swift.Error {
    case invalidFilename
    case expectedJobSubmissionMissing
  }

  typealias Key = JobKey
  typealias Value = Data

  struct SubmittedJobPayload {
    var job: any SubmittableJob
    var deduplicationExpiration: Date
  }

  public let location: URL
  
  private let lock: AsyncSemaphore
  private let jobTypeResolver: SubmittableJobTypeResolver
  private let jobEncoder: CBOREncoder
  private let jobDecoder: CBORDecoder

  public init(location: URL, jobTypeResolver: SubmittableJobTypeResolver) throws {
    self.location = location
    self.lock = AsyncSemaphore(value: 1)
    self.jobTypeResolver = jobTypeResolver

    self.jobEncoder = CBOREncoder()
    self.jobEncoder.userInfo[submittableJobTypeResolverKey] = jobTypeResolver

    self.jobDecoder = CBORDecoder()
    self.jobDecoder.userInfo[submittableJobTypeResolverKey] = jobTypeResolver

    try FileManager.default.setAttributes([.type: UTType.package.identifier], ofItemAtPath: location.path)

    let jobsURL = url(forGroup: .jobs)
    try FileManager.default.createDirectory(at: jobsURL, withIntermediateDirectories: true)
  }

  func transaction<R>(operation: () async throws -> R) async throws -> R {
    try await lock.wait()
    defer { lock.signal() }
    return try await operation()
  }

  enum EntryGroup: PathConvertible {
    case jobs
    case jobPackage(id: JobID)

    var path: String {
      switch self {
      case .jobs:
        return "jobs"
      case .jobPackage(id: let jobID):
        return Entry.jobPackage(id: jobID).path
      }
    }
  }

  enum EntryKind: String, CustomStringConvertible {
    case jobPackage = "job"
    case jobSubmission = "job-submission"
    case jobResult = "job-result"

    var description: String { rawValue }
  }

  enum Entry: PathConvertible {
    case jobPackage(id: JobID)
    case jobSubmission(id: JobID)
    case jobResult(key: JobKey)

    var kind: EntryKind {
      switch self {
      case .jobPackage:
        return .jobPackage
      case .jobSubmission:
        return .jobSubmission
      case .jobResult:
        return .jobResult
      }
    }

    var group: EntryGroup {
      switch self {
      case .jobPackage:
        return .jobs
      case .jobSubmission(id: let id):
        return .jobPackage(id: id)
      case .jobResult(let key):
        return .jobPackage(id: key.id)
      }
    }

    var path: String {
      return "\(group)/\(fileName).\(kind)"
    }

    var fileName: String {
      switch self {
      case .jobPackage(id: let id):
        return "\(id)"
      case .jobSubmission:
        return "_"
      case .jobResult(key: let key):
        return "\(key.fingerprint.base64UrlEncodedString())#\(key.tags.joined(separator: ","))"
      }
    }
  }

  func url(forGroup group: EntryGroup) -> URL {
    location.appendingPathComponent(group.path)
  }

  func url(for entry: Entry) -> URL {
    location.appendingPathComponent(entry.path)
  }

  func url(forSubmission id: JobID) -> URL {
    url(for: .jobSubmission(id: id))
  }

  static let listGroupOptions: FileManager.DirectoryEnumerationOptions = [
    .skipsHiddenFiles,
    .skipsPackageDescendants,
    .skipsSubdirectoryDescendants,
    .producesRelativePathURLs
  ]

  func urls(kind: EntryKind, in group: EntryGroup) throws -> Set<URL> {
    let urls = try FileManager.default.contentsOfDirectory(at: url(forGroup: group),
                                                           includingPropertiesForKeys: [],
                                                           options: Self.listGroupOptions)
    return Set(urls.filter { $0.pathExtension == kind.rawValue })
  }

  func jobID(from url: URL) throws -> JobID {
    guard let jobID = JobID(string: url.deletingPathExtension().lastPathComponent) else {
      throw Error.invalidFilename
    }
    return jobID
  }

  func jobKey(from url: URL, for jobID: JobID) throws -> JobKey {
    
    let parts = url.deletingPathExtension().lastPathComponent.split(separator: "#")

    guard parts.count > 0 && parts.count <= 2 else {
      throw Error.invalidFilename
    }

    guard let fingerprint = Data(base64UrlEncoded: String(parts[0])) else {
      throw Error.invalidFilename
    }

    let tags = parts.count == 2 ? parts[1].split(separator: ",").map(String.init) : []

    return JobKey(id: jobID, fingerprint: fingerprint, tags: tags)
  }

  // MARK: SubmittableJobStore

  var jobCount: Int {
    get async throws {
      try urls(kind: .jobPackage, in: .jobs).count
    }
  }

  private func loadPayload<Payload: Decodable>(at url: URL, as type: Payload.Type) async throws -> Payload {
    let data = try await read(from: url)
    return try jobDecoder.decode(Payload.self, from: data)
  }

  private func savePayload<Payload: Encodable>(_ payload: Payload, to url: URL, atomically: Bool) async throws {
    let data = try jobEncoder.encode(payload)
    do {
      try await write(data: data, to: url, atomically: atomically)
    }
    catch {
      throw error
    }
  }

  func loadPayloads<Payload: Decodable, Key>(items: [(Key, URL)], as type: Payload.Type) async throws -> [(Key, Payload)] {

    return try await withThrowingTaskGroup(of: (Key, Payload)?.self) { group in

      for (key, url) in items {
        group.addTask {
          
          do {
            let payload = try await self.loadPayload(at: url, as: Payload.self)

            return (key, payload)
          }
          catch {
            logger.error(
              """
              Failed to load payload: \
              type=\(type, privacy: .public), \
              url=\(url, privacy: .public), \
              error=\(error, privacy: .public)
              """
            )
            return nil
          }
        }
      }

      var payloads: [(Key, Payload)] = []
      for try await (key, payload) in group.compactMap({ $0 }) {
        payloads.append((key, payload))
      }
      return payloads
    }
  }

  private func loadJob(at url: URL, as id: JobID) async throws -> SubmittedJob? {
    do {

      let payload = try await loadPayload(at: url, as: SubmittedJobPayload.self)

      return (payload.job, id, payload.deduplicationExpiration)
    }
    catch CocoaError.fileNoSuchFile {
      return nil
    }
  }

  func loadJob(id: JobID) async throws -> SubmittedJob? {
    return try await loadJob(at: url(forSubmission: id), as: id)
  }

  func loadJobs() async throws -> [SubmittedJob] {
    let jobPkgURLs = try urls(kind: .jobPackage, in: .jobs)
    let jobIDs = try jobPkgURLs.map { try jobID(from: $0) }
    let items = jobIDs.map { ($0, url(forSubmission: $0)) }
    let payloads = try await loadPayloads(items: items, as: SubmittedJobPayload.self)
    return payloads.map { ($1.job, $0, $1.deduplicationExpiration) }
  }

  func loadJob(jobID: JobID) async throws -> SubmittedJob {
    let jobURL = url(for: .jobSubmission(id: jobID))
    let payload = try await loadPayload(at: jobURL, as: SubmittedJobPayload.self)
    return (payload.job, jobID, payload.deduplicationExpiration)
  }

  func loadJobResults(for jobID: JobID) async throws -> [JobKey: Data] {
    do {
      let urls = try urls(kind: .jobResult, in: .jobPackage(id: jobID))
      let items = try urls.map { (try jobKey(from: $0, for: jobID), $0) }
      let payloads = try await loadPayloads(items: items, as: Data.self)
      return Dictionary(uniqueKeysWithValues: payloads)
    }
    catch let error as CocoaError where isJobNonExistentError(error)  {
      return [:]
    }

    func isJobNonExistentError(_ error: CocoaError) -> Bool {
      guard error.code == .fileReadNoSuchFile, let failedURL = error.userInfo[NSURLErrorKey] as? URL else {
        return false
      }
      return failedURL == url(for: .jobPackage(id: jobID))
    }
  }

  func saveJob(_ job: some SubmittableJob, as jobID: JobID, deduplicationExpiration: Date) async throws -> Bool {

    let jobPayload = SubmittedJobPayload(job: job, deduplicationExpiration: deduplicationExpiration)

    let jobPkgURL = url(for: .jobPackage(id: jobID))
    let jobSubmissionURL = url(for: .jobSubmission(id: jobID))
    let jobSubmissionPreURL = jobSubmissionURL.appendingPathExtension(UniqueID.generateString())

    try FileManager.default.createDirectory(at: jobPkgURL, withIntermediateDirectories: true)

    try await savePayload(jobPayload, to: jobSubmissionPreURL, atomically: false)
    defer { try? FileManager.default.removeItem(at: jobSubmissionPreURL) }

    return try await transaction {

      // Create (via link) the submission
      do {

        try FileManager.default.linkItem(at: jobSubmissionPreURL, to: jobSubmissionURL)

        return true
      }
      catch CocoaError.fileWriteFileExists {
        // File already exists... continue to check for duplication
      }

      // Load current submission to check expiration
      guard let current = try await loadJob(at: jobSubmissionURL, as: jobID) else {
        // While we were waiting the file disappeared, meaning it expired sometime
        // after we started checking. Return false to signify it was a duplicate when
        // the check started
        return false
      }

      // Explicitly check for duplication
      if current.deduplicationExpiration > .now {
        return false
      }

      // Update submission
      do {
        try FileManager.default.removeItem(at: jobSubmissionURL)
      }
      catch CocoaError.fileNoSuchFile {
        // Ignore... submission must have expired (which we already know)
      }

      try FileManager.default.linkItem(at: jobSubmissionPreURL, to: jobSubmissionURL)

      return true
    }
  }

  func removeJob(for id: JobID) async throws {
    do {
      let url = url(for: .jobPackage(id: id))
      try FileManager.default.removeItem(at: url)
    }
    catch CocoaError.fileNoSuchFile {
      // Ignore...
    }
  }


  // MARK: RegisterCacheStore

  func value(forKey key: Key) async throws -> Data? {
    do {
      let url = url(for: .jobResult(key: key))
      return try await loadPayload(at: url, as: Data.self)
    }
    catch CocoaError.fileNoSuchFile {
      return nil
    }
  }

  func updateValue(_ value: Data, forKey key: JobKey) async throws {
    let url = url(for: .jobResult(key: key))
    try await savePayload(value, to: url, atomically: true)
  }

  func removeValue(forKey key: JobKey) async throws {
    do {
      let url = url(for: .jobResult(key: key))
      try FileManager.default.removeItem(at: url)
    }
    catch CocoaError.fileNoSuchFile {
      // Ignore...
    }
  }

}

extension JobDirectorStore.SubmittedJobPayload: Codable {

  enum CodingKeys: String, CodingKey {
    case job = "job"
    case deduplicationExpiration = "exp"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.job = try container.decode(SubmittableJobWrapper.self, forKey: .job).job
    self.deduplicationExpiration = try container.decode(Date.self, forKey: .deduplicationExpiration)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(SubmittableJobWrapper(job: job), forKey: .job)
    try container.encode(deduplicationExpiration, forKey: .deduplicationExpiration)
  }

}

protocol PathConvertible: CustomStringConvertible {
  var path: String { get }
}

extension PathConvertible {
  var description: String { path }
}


private func read(from url: URL) async throws -> Data {
  let source = try FileSource(url: url)
  defer { try? source.close() }
  let data = DataSink()
  try await source.pipe(to: data)
  return data.data
}

private func write(data: Data, to url: URL, atomically: Bool) async throws {

  let source = DataSource(data: data)

  guard atomically else {

    if !FileManager.default.createFile(atPath: url.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }

    let sink = try FileSink(url: url)
    defer { try? sink.close() }
    
    try await source.pipe(to: sink)

    return
  }

  let tmp = url.appendingPathExtension(UniqueID.generateString())

  if !FileManager.default.createFile(atPath: tmp.path, contents: nil) {
    throw CocoaError(.fileWriteUnknown)
  }
  defer { try? FileManager.default.removeItem(at: tmp)  }

  let sink = try FileSink(url: tmp)
  defer { try? sink.close() }

  try await sink.write(data: data)

  try FileManager.default.linkItem(at: tmp, to: url)
}
