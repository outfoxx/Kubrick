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
      case expiration
    }

    var id: UUID
    var type: String
    var data: Data
    var expiration: Date

    init(id: UUID, type: String, data: Data, expiration: Date) {
      self.id = id
      self.type = type
      self.data = data
      self.expiration = expiration
    }

    init(row: Row) throws {
      id = row[Columns.id]
      type = row[Columns.type]
      data = row[Columns.data]
      expiration = row[Columns.expiration]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.id] = id
      container[Columns.type] = type
      container[Columns.data] = data
      container[Columns.expiration] = expiration
    }

    static func filter(id: JobID) -> QueryInterfaceRequest<Self> {
      return filter(Columns.id == id.uuid)
    }

  }

  struct JobResultEntry: FetchableRecord, PersistableRecord, TableRecord {

    static let databaseTableName = "job_result"

    enum Columns: String, ColumnExpression {
      case submission
      case fingerprint
      case result
    }

    var jobKey: JobKey
    var result: Data

    init(jobKey: JobKey, result: Data) {
      self.jobKey = jobKey
      self.result = result
    }

    init(row: Row) throws {
      let submission: UUID = row[Columns.submission]
      let fingerprint: Data = row[Columns.fingerprint]
      jobKey = JobKey(submission: .init(uuid: submission), fingerprint: fingerprint)
      result = row[Columns.result]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.submission] = jobKey.submission.uuid
      container[Columns.fingerprint] = jobKey.fingerprint
      container[Columns.result] = result
    }

    static func filter(submission: JobID) -> QueryInterfaceRequest<Self> {
      return filter(Columns.submission == submission.uuid)
    }

    static func filter(jobKey: JobKey) -> QueryInterfaceRequest<Self> {
      return filter(Columns.submission == jobKey.submission.uuid && Columns.fingerprint == jobKey.fingerprint)
    }

  }

  private let dbQueue: DatabasePool
  private let typeResolver: SubmittableJobTypeResolver

  public convenience init(location: URL, typeResolver: SubmittableJobTypeResolver) throws {
    self.init(dbQueue: try Self.db(path: location.path), typeResolver: typeResolver)
  }

  init(dbQueue: DatabasePool, typeResolver: SubmittableJobTypeResolver) {
    self.dbQueue = dbQueue
    self.typeResolver = typeResolver
  }


  // MARK: SubmittableJobStore

  func loadJobs() async throws -> [SubmittedJob] {
    let entries = try await dbQueue.read { db in
      try SubmittedJobEntry.fetchAll(db)
    }
    return try entries.map {
      let type = try typeResolver.resolve(typeId: $0.type)
      return (try type.init(data: $0.data), JobID(uuid: $0.id), $0.expiration)
    }
  }

  func saveJob(_ job: some SubmittableJob, id: JobID, expiration: Date) async throws -> Bool {
    try await dbQueue.write { db in

      let data = try job.encode()

      if let current = try SubmittedJobEntry.filter(id: id).fetchOne(db) {

        if current.expiration > .now {
      
          // Return current unexpired entry
          return false
        }
      }

      // Remove current results (if any)
      try JobResultEntry.filter(submission: id).deleteAll(db)

      // Insert or update entry

      let entry = SubmittedJobEntry(id: id.uuid, type: type(of: job).typeId, data: data, expiration: expiration)
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
        JobResultEntry.Columns.submission.rawValue: key.submission.description.databaseValue,
        JobResultEntry.Columns.fingerprint.rawValue: key.fingerprint.databaseValue,
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
        JobResultEntry.Columns.submission.rawValue: key.submission.description.databaseValue,
        JobResultEntry.Columns.fingerprint.rawValue: key.fingerprint.databaseValue,
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
        td.column(SubmittedJobEntry.Columns.id.rawValue, .text)
        td.column(SubmittedJobEntry.Columns.type.rawValue, .text)
        td.column(SubmittedJobEntry.Columns.data.rawValue, .blob)
        td.column(SubmittedJobEntry.Columns.expiration.rawValue, .datetime)
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
                      onDelete: .cascade,
                      onUpdate: .cascade)
      }

      try db.create(indexOn: JobResultEntry.databaseTableName, columns: [JobResultEntry.Columns.submission.rawValue])

    }

    return migrator
  }

}
