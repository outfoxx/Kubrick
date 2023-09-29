//
//  JobHashable.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCBOR


public protocol JobHashable {

  func jobHash<Hasher: JobHasher>(into hasher: inout Hasher) throws

}


extension JobHashable where Self: Encodable {

  public func jobHash<Hasher: JobHasher>(into hasher: inout Hasher) throws {
    hasher.update(data: try CBOREncoder.deterministic.encode(self))
  }

}


extension Optional: JobHashable where Wrapped: JobHashable {

  public func jobHash<Hasher: JobHasher>(into hasher: inout Hasher) throws {
    switch self {
    case .none:
      hasher.update(data: Data())

    case .some(let value):
      try value.jobHash(into: &hasher)
    }
  }

}

extension Result: JobHashable where Success: JobHashable {

  public func jobHash<Hasher: JobHasher>(into hasher: inout Hasher) throws {
    switch self {
    case .success(let value):
      try value.jobHash(into: &hasher)

    case .failure(let error):
      try hasher.update(data: CBOREncoder.deterministic.encode(ErrorBox(error)))
    }
  }

}

extension Dictionary: JobHashable where Self: Encodable, Key: JobHashable, Value: JobHashable {}

extension Array: JobHashable where Self: Encodable, Element: JobHashable {}

extension Set: JobHashable where Self: Encodable, Element: JobHashable, Element: Comparable {

  public func jobHash<Hasher: JobHasher>(into hasher: inout Hasher) throws {
    try sorted().jobHash(into: &hasher)
  }

}

extension Bool: JobHashable {}

extension Int: JobHashable {}
extension Int8: JobHashable {}
extension Int16: JobHashable {}
extension Int32: JobHashable {}
extension Int64: JobHashable {}

extension UInt: JobHashable {}
extension UInt8: JobHashable {}
extension UInt16: JobHashable {}
extension UInt32: JobHashable {}
extension UInt64: JobHashable {}

extension Float: JobHashable {}
extension Double: JobHashable {}

extension String: JobHashable {}

extension Data: JobHashable {}

extension URL: JobHashable {}

extension UUID: JobHashable {}

extension Date: JobHashable {}
