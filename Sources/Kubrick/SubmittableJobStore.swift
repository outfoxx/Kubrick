//
//  SubmittableJobStore.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


typealias SubmittedJob = (job: any SubmittableJob, id: JobID, deduplicationExpiration: Date)


protocol SubmittableJobStore {

  var jobCount: Int { get async throws }

  func loadJobs() async throws -> [SubmittedJob]

  func saveJob(_ job: some SubmittableJob, as jobID: JobID, deduplicationExpiration: Date) async throws -> Bool

  func removeJob(for id: JobID) async throws

}
