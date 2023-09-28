//
//  JobID.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation
import PotentCBOR


public typealias JobID = UniqueID


public extension JobID {

  static func builder() -> Builder { Builder() }

  struct Builder {

    static let uuidNamespace = UUID(uuid: (0x7F, 0x27, 0xF1, 0xF8, 0xC2, 0x1B, 0x42, 0x3D,
                                           0xBE, 0xA5, 0x93, 0x4B, 0x9C, 0xF5, 0x59, 0xD2))

    var name = Data()

    public func update<Value: Encodable>(value: Value) throws -> Self {
      var name = name
      name.append(try CBOREncoder.deterministic.encode(value))
      return Builder(name: name)
    }

    public func build() -> JobID {
      return JobID(uuid: UUID(namespace: Self.uuidNamespace, name: name))
    }
    
  }

}
