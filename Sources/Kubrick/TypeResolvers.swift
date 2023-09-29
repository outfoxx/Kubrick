//
//  TypeResolvers.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol SubmittableJobTypeResolver {

  func resolve(jobTypeId: String) throws -> any SubmittableJob.Type

}


public protocol JobErrorTypeResolver {

  func resolve(errorDomain: String) -> JobError.Type?

}


public struct TypeNameTypeResolver: SubmittableJobTypeResolver, JobErrorTypeResolver {

  enum Error: Swift.Error {
    case unknownJobType
  }

  var jobs: [String: any SubmittableJob.Type]
  var errors: [String: any JobError.Type]

  public init(jobs: [any SubmittableJob.Type], errors: [any JobError.Type] = []) {
    self.jobs = Dictionary(uniqueKeysWithValues: jobs.map { (String(reflecting: $0), $0) })
    self.errors = Dictionary(uniqueKeysWithValues: errors.map { (String(reflecting: $0), $0) })
  }

  public func resolve(jobTypeId: String) throws -> any SubmittableJob.Type {
    guard let jobType = jobs[jobTypeId] else {
      throw Error.unknownJobType
    }
    return jobType
  }

  public func resolve(errorDomain: String) -> JobError.Type? {
    return errors[errorDomain]
  }

}
