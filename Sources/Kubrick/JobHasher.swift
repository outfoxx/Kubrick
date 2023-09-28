//
//  JobHasher.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation


public typealias JobHasher = HashFunction


extension JobHasher {

  mutating func update(value: some JobHashable) throws {
    try value.jobHash(into: &self)
  }

  mutating func update(type: Any.Type) {
    update(string: String(describing: type))
  }

  mutating func update(string: String) {
    update(data: string.data(using: .utf8) ?? Data())
  }

  func finalized() -> Data {
    return finalize().withUnsafeBytes { Data($0) }
  }

}
