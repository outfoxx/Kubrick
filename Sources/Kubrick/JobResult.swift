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


#if !DISABLE_RESULT_REPLACE

public enum ExecuteResult<Success> {
  case success(Success)
  case failure(Error)

  public func get() throws -> Success {
    switch self {
    case .success(let value):
      return value
    case .failure(let error):
      throw error
    }
  }

}

#else

public typealias ExecuteResult<Success> = Swift.Result<Success, Error>

#endif


public typealias JobResult<Success: JobValue> = ExecuteResult<Success>
public typealias AnyJobResult = ExecuteResult<any JobValue>


extension ExecuteResult: Codable where Success: Codable {

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
      let errorBox = try container.decode(JobErrorBox.self, forKey: .failure)
      self = .failure(errorBox.error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let value):
      try container.encode(value, forKey: .success)
    case .failure(let error):
      try container.encode(JobErrorBox(error), forKey: .failure)
    }
  }

}


extension ExecuteResult {

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

  var wrapped: ExecuteResult<Success?> {
    switch self {
    case .success(let value): return .success(value)
    case .failure(let error): return .failure(error)
    }
  }

  func unwrapNonFailed<Value: JobValue>(_ type: Value.Type = Value.self) throws -> Value {
    switch self {
    case .success(let value):
      guard let value = value as? Value else {
        throw JobExecutionError.invariantViolation(.inputResultInvalid)
      }
      return value

    case .failure:
      throw JobExecutionError.invariantViolation(.executeInvokedWithFailedInput)
    }
  }

}


extension Result: Codable where Success: Codable {

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
      let errorBox = try container.decode(JobErrorBox.self, forKey: .failure)
      guard let error = errorBox.error as? Failure else {
        throw DecodingError.typeMismatch(at: container.codingPath + [CodingKeys.failure],
                                         expectation: Failure.self,
                                         reality: errorBox.error)
      }
      self = .failure(error)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let value):
      try container.encode(value, forKey: .success)
    case .failure(let error):
      try container.encode(JobErrorBox(error), forKey: .failure)
    }
  }

}
