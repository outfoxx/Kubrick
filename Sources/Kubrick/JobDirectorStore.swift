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
    }

    var id: UUID
    var type: String
    var data: Data

    init(id: UUID, type: String, data: Data) {
      self.id = id
      self.type = type
      self.data = data
    }

    init(row: Row) throws {
      id = row[Columns.id]
      type = row[Columns.type]
      data = row[Columns.data]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.id] = id
      container[Columns.type] = type
      container[Columns.data] = data
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
      let submission = JobID(string: row[Columns.submission])!
      let fingerprint: Data = row[Columns.fingerprint]
      jobKey = JobKey(submission: submission, fingerprint: fingerprint)
      result = row[Columns.result]
    }

    func encode(to container: inout PersistenceContainer) throws {
      container[Columns.submission] = jobKey.submission.description
      container[Columns.fingerprint] = jobKey.fingerprint
      container[Columns.result] = result
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

  func loadJobs() async throws -> [(UUID, any SubmittableJob)] {
    let entries = try await dbQueue.read { db in
      try SubmittedJobEntry.fetchAll(db)
    }
    return try entries.map {
      let type = try typeResolver.resolve(typeId: $0.type)
      return ($0.id, try type.init(data: $0.data))
    }
  }

  func saveJob(_ job: some SubmittableJob, id: UUID) async throws {
    let data = try job.encode()
    try await dbQueue.write { db in
      let record = SubmittedJobEntry(id: id, type: type(of: job).typeId, data: data)
      try record.save(db, onConflict: .replace)
    }
  }

  func removeJob(for id: UUID) async throws {
    _ = try await dbQueue.write { db in
      try SubmittedJobEntry.deleteOne(db, id: id)
      try JobResultEntry.filter(JobResultEntry.Columns.submission == id).deleteAll(db)
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
      try db.create(table: JobResultEntry.databaseTableName) { td in
        td.column(JobResultEntry.Columns.submission.rawValue, .text)
        td.column(JobResultEntry.Columns.fingerprint.rawValue, .blob)
        td.column(JobResultEntry.Columns.result.rawValue, .blob)
        td.primaryKey([
          JobResultEntry.Columns.submission.rawValue,
          JobResultEntry.Columns.fingerprint.rawValue,
        ])
      }

      try db.create(table: SubmittedJobEntry.databaseTableName) { td in
        td.column(SubmittedJobEntry.Columns.id.rawValue, .text)
        td.column(SubmittedJobEntry.Columns.type.rawValue, .text)
        td.column(SubmittedJobEntry.Columns.data.rawValue, .blob)
        td.primaryKey([SubmittedJobEntry.Columns.id.rawValue])
      }
    }

    return migrator
  }

}
