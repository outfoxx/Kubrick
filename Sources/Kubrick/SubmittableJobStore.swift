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


public protocol SubmittableJobStore {

  func loadJobs() async throws -> [(UUID, any SubmittableJob)]

  func saveJob(_ job: some SubmittableJob, id: UUID) async throws
  func removeJob(for id: UUID) async throws

}
