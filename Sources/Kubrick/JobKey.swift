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
  public var submission: JobID
  public var fingerprint: Data

  public init(submission: JobID, fingerprint: Data) {
    self.submission = submission
    self.fingerprint = fingerprint
  }
}


extension JobKey: CustomStringConvertible {

  public var description: String {
    let fingerprint = fingerprint.base64UrlEncodedString()
    return "\(Self.scheme)://\(submission)/\(fingerprint)"
  }

  public init?(string: String) {
    guard
      let result = Self.regex.matches(string, groupNames: ["jobid", "fingerprint"]),
      let jobID = result["jobid"].flatMap({ JobID(string: String($0)) }),
      let jobFingerprint = result["fingerprint"].flatMap({ Data(base64UrlEncoded: String($0)) })
    else {
      return nil
    }
    self.submission = jobID
    self.fingerprint = jobFingerprint
  }

  static let scheme = "job"
  static let regex = NSRegularExpression(#"\#(scheme)://(?<jobid>[a-zA-Z0-9]+)/(?<fingerprint>[a-zA-Z0-9-_]+)"#)

}
