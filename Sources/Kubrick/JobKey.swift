//
//  JobKey.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import PotentCodables
import PotentCBOR
import RegexBuilder


public struct JobKey: Equatable, Hashable, Codable {
  public var id: JobID
  public var fingerprint: Data
  public var tags: [String]

  public init(id: JobID, fingerprint: Data, tags: [String] = []) {
    self.id = id
    self.fingerprint = fingerprint
    self.tags = tags
  }
}


extension JobKey: CustomStringConvertible {

  public var description: String {
    let fingerprint = fingerprint.base64UrlEncodedString()
    let tags = tags.isEmpty ? "" : "#\(tags.joined(separator: ","))"
    return "\(Self.scheme)://\(id)/\(fingerprint)\(tags)"
  }

  public init?(string: String) {
    guard
      let result = Self.regex.matches(string, groupNames: ["jobid", "fingerprint", "tags"]),
      let jobID = result["jobid"].flatMap({ JobID(string: String($0)) }),
      let jobFingerprint = result["fingerprint"].flatMap({ Data(base64UrlEncoded: String($0)) }),
      let tags = result["tags"].flatMap(String.init)
    else {
      return nil
    }
    self.id = jobID
    self.fingerprint = jobFingerprint
    self.tags = tags.split(separator: ",").map(String.init)
  }

  static let scheme = "job"
  static let regex = NSRegularExpression(
    #"\#(scheme)://(?<jobid>[a-zA-Z0-9]+)/(?<fingerprint>[a-zA-Z0-9-_]+)(#(?<tags>[\w\-]+(,[\w\-]+)*))?"#
  )

}
