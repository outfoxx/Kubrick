//
//  JobDirectorID.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


/// Identifier for a ``JobDirector``.
///
/// Identifiers can be anything but have a restricted character-set
/// to ensure it it's valid for its many uses (e.g. filename, URL,
/// persistence, etc.)
///
public struct JobDirectorID: RawRepresentable, Hashable {

  public private(set) var rawValue: String

  /// Initializes an identifier from a provided string.
  ///
  /// The initializer validates the string against the restricted
  /// character-set and fails if the string is invalid.
  ///
  /// - Note: Identifiers are only allowed to use the following
  /// characters: `a-z`, `A-Z`, `0-9`, `_` & `-`. Unicode underscores
  /// and dashes are allowed.
  ///
  /// - Parameter rawValue: Identifier value.
  ///
  public init?(rawValue: String) {

    if !Self.validate(string: rawValue) {
      return nil
    }

    self.rawValue = rawValue
  }

  /// Initializes an identifier from a provided string.
  ///
  /// The initializer validates the string against the restricted
  /// character-set and fails if the string is invalid.
  ///
  /// - Note: Identifiers are only allowed to use the following
  /// characters: `a-z`, `A-Z`, `0-9`, `_` & `-`. Unicode characters
  /// are _not_ allowed.
  ///
  /// - Parameter rawValue: Identifier value.
  ///
  public init?(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }

  /// Generates a unique, random identifier.
  ///
  /// - Returns: Generated random identifier
  ///
  public static func generate() -> JobDirectorID {
    JobDirectorID(validated: UniqueID.generateString())
  }

  init(validated: String) {
    self.rawValue = validated
  }

}


extension JobDirectorID: CustomStringConvertible {

  public var description: String { rawValue }

}


extension JobDirectorID {

  static let regex = NSRegularExpression(#"[\w-]+"#)

  /// Validates a string is a valid identifier.
  ///
  /// - Parameter string: String to validate.
  /// - Returns: `true` if `string` is valid, `false` otherwise.
  ///
  public static func validate(string: String) -> Bool {
    return Self.regex.matches(string) != nil
  }

}


extension JobDirectorID: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let value = JobDirectorID(rawValue: string) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid job director id")
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

}
