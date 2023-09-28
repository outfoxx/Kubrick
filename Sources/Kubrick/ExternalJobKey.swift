//
//  ExternalJobKey.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation

/// Uniquely identifies a specific job across directors.
///
/// Suitable for persisting and interfacing with external
/// services that survive across process execution.
///
public struct ExternalJobKey: Equatable {

  /// ID of the ``JobDirector`` that is executing the ``Job``
  public var directorId: JobDirectorID

  /// Key of executing job
  public var jobKey: JobKey
  
  /// Initialize from ``JobDirectorID`` and ``JobKey``.
  ///
  /// - Parameters:
  ///   - directorId: ID of the direct executing the `jobKey`
  ///   - jobKey: Key of executing job
  public init(directorId: JobDirectorID, jobKey: JobKey) {
    self.directorId = directorId
    self.jobKey = jobKey
  }

  /// Initialize from external string representation.
  ///
  /// - Parameters:
  ///   - string: External string representation
  ///
  public init?(string: String) {
    guard let value = Self.parse(string: string) else {
      return nil
    }
    self = value
  }
  
  /// External string representation.
  public var value: String {"\(Self.urlScheme)://\(directorId)#\(jobKey)" }

}


extension ExternalJobKey: CustomStringConvertible {

  public var description: String { value }

}


extension ExternalJobKey: Codable {

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    
    guard let value = ExternalJobKey(string: string) else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid external job key")
    }
    
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

}


extension ExternalJobKey {

  static let urlScheme = "director"
  static let directorIdRegex = JobDirectorID.regex
  static let regex = NSRegularExpression(#"\#(urlScheme)://(?<directorid>\#(directorIdRegex.pattern))#(?<jobkey>.*)"#)

  /// Parses an external string represtation of an ``ExternalJobKey``.
  ///
  /// - Parameter string: External string represtation
  /// - Returns: Parsed key or `nil` if the provided string is invalid.
  ///
  public static func parse(string: String) -> ExternalJobKey? {

    guard
      let result = Self.regex.matches(string, groupNames: ["directorid", "jobkey"]),
      let directorId = result["directorid"].flatMap({ JobDirectorID(String($0)) }),
      let jobKey = result["jobkey"].flatMap({ JobKey(string: String($0)) })
    else {
      return nil
    }

    return ExternalJobKey(directorId: directorId, jobKey: jobKey)
  }
}
