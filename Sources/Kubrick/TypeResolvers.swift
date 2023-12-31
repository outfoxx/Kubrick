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

  func typeId(of jobType: any SubmittableJob.Type) -> String
  func resolve(jobTypeId: String) throws -> any SubmittableJob.Type

}


public let submittableJobTypeResolverKey =
  CodingUserInfoKey(rawValue: String(reflecting: SubmittableJobTypeResolver.self))!



public protocol JobErrorTypeResolver {


  func resolve(errorDomain: String) -> JobError.Type?

}

public let jobErrorTypeResolverKey = CodingUserInfoKey(rawValue: String(reflecting: JobErrorTypeResolver.self))!


public struct TypeNameSubmittableJobTypeResolver: SubmittableJobTypeResolver {

  enum Error: JobError {
    case unknownJobType
  }

  var jobs: [String: any SubmittableJob.Type] = [:]

  public init(jobs: [any SubmittableJob.Type]) {
    self.jobs = Dictionary(uniqueKeysWithValues: jobs.map { (typeId(of: $0), $0) })
  }

  public func typeId(of jobType: any SubmittableJob.Type) -> String {
    return String(reflecting: jobType)
  }

  public func resolve(jobTypeId: String) throws -> any SubmittableJob.Type {
    guard let jobType = jobs[jobTypeId] else {
      throw Error.unknownJobType
    }
    return jobType
  }

}


public struct TypeNameJobErrorTypeResolver: JobErrorTypeResolver {

  var errors: [String: any JobError.Type]

  public init(errors: [any JobError.Type] = []) {
    self.errors = Dictionary(uniqueKeysWithValues: errors.map { (String(reflecting: $0), $0) })
  }

  public func resolve(errorDomain: String) -> JobError.Type? {
    return errors[errorDomain]
  }

}


public struct TypeNameTypeResolver: SubmittableJobTypeResolver, JobErrorTypeResolver {

  var jobs: SubmittableJobTypeResolver
  var errors: JobErrorTypeResolver

  public init(jobs: [any SubmittableJob.Type], errors: [any JobError.Type] = []) {
    self.jobs = TypeNameSubmittableJobTypeResolver(jobs: jobs)
    self.errors = TypeNameJobErrorTypeResolver(errors: errors)
  }

  public func typeId(of jobType: any SubmittableJob.Type) -> String {
    return jobs.typeId(of: jobType)
  }

  public func resolve(jobTypeId: String) throws -> any SubmittableJob.Type {
    return try jobs.resolve(jobTypeId: jobTypeId)
  }

  public func resolve(errorDomain: String) -> JobError.Type? {
    return errors.resolve(errorDomain: errorDomain)
  }

}


struct MultiJobErrorTypeResolver: JobErrorTypeResolver {

  let resolvers: [any JobErrorTypeResolver]

  func resolve(errorDomain: String) -> JobError.Type? {
    for resolver in resolvers {
      if let errorType = resolver.resolve(errorDomain: errorDomain) {
        return errorType
      }
    }
    return nil
  }

}
