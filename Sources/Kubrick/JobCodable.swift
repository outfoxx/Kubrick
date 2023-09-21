//
//  JobCodable.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol JobCodable {
  static func restore(from decoder: Decoder, environment: JobEnvironment) throws -> Self
  static func save(_ value: Self, to encoder: Encoder, environment: JobEnvironment) throws
}


extension JobCodable where Self: Codable {
  static func restore(from decoder: Decoder, environment: JobEnvironment) throws -> Self {
    return try Self.init(from: decoder)
  }
  static func save(_ value: Self, to encoder: Encoder, environment: JobEnvironment) throws {
    try value.encode(to: encoder)
  }
}
