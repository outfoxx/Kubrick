//
//  JobErrorBox.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables


public struct JobErrorBox: Codable, JobHashable {

  var error: any Error

  public init(_ error: any Error) {
    self.error = error
  }

  enum CodingKeys: String, CodingKey {
    case storage
    case domain
    case error
  }

  enum Storage: String, Codable {
    case codable
    case nsError
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storage = try container.decode(Storage.self, forKey: .storage)
    switch storage {
    case .codable:
      let domain = try container.decode(String.self, forKey: .domain)
      guard let errorType = Self.resolveType(errorDomain: domain, for: decoder) else {
        throw DecodingError.dataCorruptedError(forKey: .error,
                                               in: container,
                                               debugDescription: "Codable error not registered")
      }
      self.error = try container.decode(errorType, forKey: .error)

    case .nsError:
      self.error = try container.decode(forKey: .error, using: NSErrorCodingTransformer.instance)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let domain = error._domain
    if Self.resolveType(errorDomain: domain, for: encoder) != nil, let jobError = error as? Codable {
      try container.encode(Storage.codable, forKey: .storage)
      try container.encode(domain, forKey: .domain)
      try container.encode(jobError, forKey: .error)
    }
    else {
      try container.encode(Storage.nsError, forKey: .storage)
      try container.encode(error as NSError, forKey: .error, using: NSErrorCodingTransformer.instance)
    }
  }

  static func resolveType(errorDomain: String, for decoder: Decoder) -> JobError.Type? {
    guard let resolver = decoder.userInfo[jobErrorTypeResolverKey] as? JobErrorTypeResolver else {
      return nil
    }
    return resolver.resolve(errorDomain: errorDomain)
  }

  static func resolveType(errorDomain: String, for encoder: Encoder) -> JobError.Type? {
    guard let resolver = encoder.userInfo[jobErrorTypeResolverKey] as? JobErrorTypeResolver else {
      return nil
    }
    return resolver.resolve(errorDomain: errorDomain)
  }

}


public enum NSErrorCodingTransformer: ValueCodingTransformer {
  case instance

  enum Error: JobError {
    case unknownError
  }

  public func decode(_ value: Data) throws -> NSError {
    guard let error = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: value) else {
      return Error.unknownError as NSError
    }
    return error
  }

  public func encode(_ value: NSError) throws -> Data {

    func clean(_ value: [String: Any]) -> [String: Any] {
      return value.compactMapValues { value in
        if let error = value as? NSError {
          return NSError(domain: error.domain, code: error.code, userInfo: clean(error.userInfo))
        }
        if let dict = value as? [String: Any] {
          return clean(dict)
        }
        return value as? NSSecureCoding
      }
    }

    do {
      let cleaned = NSError(domain: value.domain, code: value.code, userInfo: clean(value.userInfo))
      return try NSKeyedArchiver.archivedData(withRootObject: cleaned, requiringSecureCoding: true)
    }
    catch {
      throw Error.unknownError
    }
  }

}
