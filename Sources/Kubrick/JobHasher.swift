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
import PotentCBOR


public typealias JobHasher = HashFunction


extension JobHasher {

  mutating func update(type: Any.Type) {
    update(string: String(describing: type))
  }

  mutating func update(string: String) {
    update(data: string.data(using: .utf8) ?? Data())
  }

  mutating func finalized() -> Data {
    return finalize().withUnsafeBytes { Data($0) }
  }

}
