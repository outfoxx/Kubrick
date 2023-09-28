//
//  JobResult.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables


public typealias JobResult<Success: JobValue> = Result<Success, Error>
public typealias AnyJobResult = Result<any JobValue, Error>


extension JobResult {

  var isSuccess: Bool {
    guard case .success = self else {
      return false
    }
    return true
  }

  var isFailure: Bool {
    guard case .failure = self else {
      return false
    }
    return true
  }

}


extension JobResult: Codable where Success: Codable {

  enum CodingKeys: CodingKey {
    case success
    case failure
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.success) {
      let value = try container.decode(Success.self, forKey: .success)
      self = .success(value)
    }
    else {
      self = .failure(try ErrorBox.decode(from: container, forKey: .failure))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let value):
      try container.encode(value, forKey: .success)
    case .failure(let error):
      try container.encode(ErrorBox(error), forKey: .failure)
    }
  }

}


public struct ErrorBox: Codable, JobHashable {
  var error: any Error

  public init(_ error: Error) {
    self.error = error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let codableType = Error.self as? Codable.Type {
      self.error = try container.decode(codableType) as! Error
    }
    else {
      self.error = try container.decode(using: NSErrorCodingTransformer.instance)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if let codableError = error as? Codable {
      try container.encode(codableError)
    }
    else {
      try container.encode(error as NSError, using: NSErrorCodingTransformer.instance)
    }
  }

  public static func decode<SpecificError: Swift.Error, CodingKeys: CodingKey>(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> SpecificError {
    let box = try container.decode(Self.self, forKey: key)
    guard let error = box.error as? SpecificError else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "Failure value has incorrect type '\(type(of: box.error))', expected '\(SpecificError.self)'"
      )
    }
    return error
  }

  public func decode<SpecificError: Swift.Error>(
    from container: inout UnkeyedDecodingContainer
  ) throws -> SpecificError {
    let box = try container.decode(Self.self)
    guard let error = box.error as? SpecificError else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Failure value has incorrect type '\(type(of: box.error))', expected '\(SpecificError.self)'"
      )
    }
    return error
  }
}


public enum NSErrorCodingTransformer: ValueCodingTransformer {
  case instance

  enum Error: Int, Swift.Error, Codable {
    case unknownError
  }

  public func decode(_ value: Data) throws -> NSError {
    guard let error = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: value) else {
      return Error.unknownError as NSError
    }
    return error
  }

  public func encode(_ value: NSError) throws -> Data {
    do {
      return try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    }
    catch {
      throw Error.unknownError
    }
  }

}


public extension AnyJobResult {

  func valueResult<Value: JobValue>(_ type: Value.Type = Value.self) throws -> JobResult<Value> {
    switch self {
    case .success(let value):
      guard let value = value as? Value else {
        throw JobError.invariantViolation(.inputResultInvalid)
      }
      return .success(value)

    case .failure(let error):
      return .failure(error)
    }
  }

}
