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
import PotentCBOR
import GRDB


class JobDirectorStore: RegisterCacheStore, SubmittableJobStore {

  typealias Key = JobKey
  typealias Value = Data

  struct SubmittedJobEntry: FetchableRecord, PersistableRecord, TableRecord, Identifiable {

    static let databaseTableName = "submitted_job"

    enum Columns: String, ColumnExpression {
      case id
      case type
      case data
      case deduplicationExpiration
    }

    var id: UUID
    var type: String
    var data: Data
    var deduplicationExpiration: Date

    init(id: JobID, type: String, data: Data, deduplicationExpiration: Date) {
      self.init(id: id.uuid, type: type, data: data, deduplicationExpiration: deduplicationExpiration)
    }

    init(id: UUID, type: String, data: Data, deduplicationExpiration: Date) {
      self.id = id
      self.type = type
      self.data = data
      self.deduplicationExpiration = deduplicationExpiration
    }

    init(row: Row) throws {
      id = row[Columns.id]
      type = row[Columns.type]
      data = row[Columns.data]
      deduplicationExpiration = row[Columns.deduplicationExpiration]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.id] = id
      container[Columns.type] = type
      container[Columns.data] = data
      container[Columns.deduplicationExpiration] = deduplicationExpiration
    }

    static func filter(id: JobID) -> QueryInterfaceRequest<Self> {
      filter(id: id.uuid)
    }

    static func filter(id: UUID) -> QueryInterfaceRequest<Self> {
      return filter(Columns.id == id)
    }

  }

  struct JobResultEntry: FetchableRecord, PersistableRecord, TableRecord {

    static let databaseTableName = "job_result"

    enum Columns: String, ColumnExpression {
      case submission
      case fingerprint
      case result
    }

    var submission: UUID
    var fingerprint: Data
    var result: Data

    var jobKey: JobKey { JobKey(submission: JobID(uuid: submission), fingerprint: fingerprint) }

    init(jobKey: JobKey, result: Data) {
      self.init(submission: jobKey.submission.uuid, fingerprint: jobKey.fingerprint, result: result)
    }

    init(submission: UUID, fingerprint: Data, result: Data) {
      self.submission = submission
      self.fingerprint = fingerprint
      self.result = result
    }

    init(row: Row) throws {
      self.submission = row[Columns.submission]
      self.fingerprint = row[Columns.fingerprint]
      self.result = row[Columns.result]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.submission] = submission
      container[Columns.fingerprint] = fingerprint
      container[Columns.result] = result
    }

    static func filter(submission: JobID) -> QueryInterfaceRequest<Self> {
      return filter(submission: submission.uuid)
    }

    static func filter(jobKey: JobKey) -> QueryInterfaceRequest<Self> {
      return filter(submission: jobKey.submission.uuid, fingerprint: jobKey.fingerprint)
    }

    static func filter(submission: UUID) -> QueryInterfaceRequest<Self> {
      return filter(Columns.submission == submission)
    }

    static func filter(submission: UUID, fingerprint: Data) -> QueryInterfaceRequest<Self> {
      return filter(Columns.submission == submission && Columns.fingerprint == fingerprint)
    }

  }

  private let dbQueue: DatabasePool
  private let jobTypeResolver: SubmittableJobTypeResolver
  private let jobEncoder: any JobEncoder
  private let jobDecoder: any JobDecoder

  public convenience init(
    location: URL,
    jobTypeResolver: SubmittableJobTypeResolver,
    jobEncoder: any JobEncoder,
    jobDecoder: any JobDecoder
  ) throws {
    self.init(dbQueue: try Self.db(path: location.path),
              jobTypeResolver: jobTypeResolver,
              jobEncoder: jobEncoder,
              jobDecoder: jobDecoder)
  }

  init(
    dbQueue: DatabasePool,
    jobTypeResolver: SubmittableJobTypeResolver,
    jobEncoder: any JobEncoder,
    jobDecoder: any JobDecoder
  ) {
    self.dbQueue = dbQueue
    self.jobTypeResolver = jobTypeResolver
    self.jobEncoder = jobEncoder
    self.jobDecoder = jobDecoder
  }


  // MARK: SubmittableJobStore

  var jobCount: Int {
    get async throws {
      try await dbQueue.read { db in
        try SubmittedJobEntry.fetchCount(db)
      }
    }
  }

  func loadJobs() async throws -> [SubmittedJob] {
    let entries = try await dbQueue.read { db in
      try SubmittedJobEntry.fetchAll(db)
    }
    return try entries.map {
      let type = try jobTypeResolver.resolve(jobTypeId: $0.type)
      return (try type.init(from: $0.data, using: jobDecoder), JobID(uuid: $0.id), $0.deduplicationExpiration)
    }
  }

  func saveJob(_ job: some SubmittableJob, id: JobID, deduplicationExpiration: Date) async throws -> Bool {
    try await dbQueue.write { db in

      let data = try job.encode(using: self.jobEncoder)

      if let current = try SubmittedJobEntry.filter(id: id).fetchOne(db) {

        if current.deduplicationExpiration > .now {

          // Return current unexpired entry
          return false
        }
      }

      // Remove current results (if any)
      try JobResultEntry.filter(submission: id).deleteAll(db)

      // Insert or update entry

      let entry = SubmittedJobEntry(id: id.uuid,
                                    type: type(of: job).typeId,
                                    data: data,
                                    deduplicationExpiration: deduplicationExpiration)

      try entry.save(db, onConflict: .replace)

      return true
    }
  }

  func removeJob(for id: JobID) async throws {
    _ = try await dbQueue.write { db in
      try SubmittedJobEntry.deleteOne(db, id: id.uuid)
    }
  }

  func loadJobResults(for id: JobID) async throws -> [JobResultEntry] {
    try await dbQueue.write { db in
      try JobResultEntry.filter(submission: id).fetchAll(db)
    }
  }


  // MARK: RegisterCacheStore

  func value(forKey key: Key) async throws -> Data? {
    try await dbQueue.read { db in
      let entry = try JobResultEntry.fetchOne(db, key: [
        JobResultEntry.Columns.submission.rawValue: key.submission.uuid,
        JobResultEntry.Columns.fingerprint.rawValue: key.fingerprint,
      ])
      return entry?.result
    }
  }

  func updateValue(_ value: Data, forKey key: JobKey) async throws {
    try await dbQueue.write { db in
      let record = JobResultEntry(jobKey: key, result: value)
      try record.save(db, onConflict: .replace)
    }
  }

  func removeValue(forKey key: JobKey) async throws {
    _ = try await dbQueue.write { db in
      try JobResultEntry.deleteOne(db, key: [
        JobResultEntry.Columns.submission.rawValue: key.submission.uuid,
        JobResultEntry.Columns.fingerprint.rawValue: key.fingerprint,
      ])
    }
  }

  func removeValues(forKeys keys: Set<JobKey>) async throws {
    _ = try await dbQueue.write { db in
      try JobResultEntry.filter(
        keys.map(\.submission.uuid).contains(JobResultEntry.Columns.submission) &&
        keys.map(\.fingerprint).contains(JobResultEntry.Columns.fingerprint)
      )
      .deleteAll(db)
    }
  }

  static func db(path: String) throws -> DatabasePool {
    var dbConfig = Configuration()
    dbConfig.journalMode = .wal
    dbConfig.busyMode = .timeout(2.5)

    let dbQueue = try DatabasePool(path: path, configuration: dbConfig)

    try migrator().migrate(dbQueue)

    return dbQueue
  }

  static func migrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration("initial") { db in

      try db.create(table: SubmittedJobEntry.databaseTableName) { td in
        td.column(SubmittedJobEntry.Columns.id.rawValue, .blob)
        td.column(SubmittedJobEntry.Columns.type.rawValue, .text)
        td.column(SubmittedJobEntry.Columns.data.rawValue, .blob)
        td.column(SubmittedJobEntry.Columns.deduplicationExpiration.rawValue, .datetime)
        td.primaryKey([SubmittedJobEntry.Columns.id.rawValue])
      }

      try db.create(table: JobResultEntry.databaseTableName) { td in
        td.column(JobResultEntry.Columns.submission.rawValue, .blob)
        td.column(JobResultEntry.Columns.fingerprint.rawValue, .blob)
        td.column(JobResultEntry.Columns.result.rawValue, .blob)
        td.primaryKey([
          JobResultEntry.Columns.submission.rawValue,
          JobResultEntry.Columns.fingerprint.rawValue,
        ])
        td.foreignKey([JobResultEntry.Columns.submission.rawValue],
                      references: SubmittedJobEntry.databaseTableName,
                      columns: [SubmittedJobEntry.Columns.id.rawValue],
                      onDelete: .cascade,
                      onUpdate: .cascade)
      }

      try db.create(indexOn: JobResultEntry.databaseTableName, columns: [JobResultEntry.Columns.submission.rawValue])

    }

    return migrator
  }

}
