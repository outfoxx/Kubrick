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


public typealias JobInputResult<Value: JobHashable> = ExecuteResult<Value>
public typealias AnyJobInputResult = ExecuteResult<any JobHashable>


public protocol JobInputDescriptor {
  
  associatedtype Value: JobHashable

  var isUnbound: Bool { get }

  var reportType: Value.Type { get }

  func resolve(
    for director: JobDirector,
    as jobID: JobID,
    tags: [String]
  ) async throws -> (id: UUID, result: JobInputResult<Value>)

}

extension JobInputDescriptor {

  public var isUnbound: Bool { false }

  public var reportType: Value.Type { Value.self }

}


public struct AdHocJobInputDescriptor<SourceJob: Job>: JobInputDescriptor {

  public var id: UUID
  public var job: SourceJob

  public init(id: UUID, job: SourceJob) {
    self.id = id
    self.job = job
  }

  public func resolve(
    for director: JobDirector,
    as jobID: JobID,
    tags: [String]
  ) async throws -> (id: UUID, result: JobInputResult<SourceJob.Value>) {
    return (id, try await director.resolve(job, as: jobID, tags: tags).result)
  }
}
