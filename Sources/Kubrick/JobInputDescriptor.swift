//
//  JobInputDescriptor.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol JobInputDescriptor {
  
  associatedtype Value: Codable

  var reportType: Value.Type { get }
  
  func resolve(for director: JobDirector, submission: JobID) async throws -> (id: UUID, result: JobResult<Value>)

}


struct AdHocJobInputDescriptor<SourceJob: Job>: JobInputDescriptor {

  var id: UUID
  var job: SourceJob

  var reportType: SourceJob.Value.Type { SourceJob.Value.self }

  func resolve(for director: JobDirector, submission: JobID) async throws -> (id: UUID, result: JobResult<SourceJob.Value>) {
    return (id, try await director.resolve(job, submission: submission).result)
  }
}
