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
      let data = try container.decode(Data.self, forKey: .failure)
      let error = NSError.decode(data)
      self = .failure(error as! Failure)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let value):
      try container.encode(value, forKey: .success)
    case .failure(let error):
      try container.encode((error as NSError).encode(), forKey: .failure)
    }
  }

}


extension NSError {

  enum CodableError: Error {
    case unknownError
  }

  func encode() throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: self as NSError, requiringSecureCoding: true)
  }



  static func decode(_ value: Data) -> Swift.Error {
    return (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: value)) ?? CodableError.unknownError
  }

}
