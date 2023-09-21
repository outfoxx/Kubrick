//
//  SubmittableJobTypeResolver.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol SubmittableJobTypeResolver {

  func resolve(typeId: String) throws -> any SubmittableJob.Type

}


public struct TypeNameJobTypeResolver: SubmittableJobTypeResolver {

  enum Error: Swift.Error {
    case unknownJobType
  }

  var types: [String: any SubmittableJob.Type]

  public init(types: [any SubmittableJob.Type]) {
    self.types = Dictionary(uniqueKeysWithValues: types.map { (String(describing: $0), $0) })
  }

  public func resolve(typeId: String) throws -> any SubmittableJob.Type {
    guard let type = types[typeId] else {
      throw Error.unknownJobType
    }
    return type
  }

}
