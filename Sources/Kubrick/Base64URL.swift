//
//  Base64URL.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation

extension Data {

  public init?(base64UrlEncoded string: String) {
    let base64String = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    self.init(base64EncodedUnpadded: base64String)
  }

  public init?(base64EncodedUnpadded string: String) {
    self.init(base64Encoded: Data.padBase64(string))
  }

  private static func padBase64(_ string: String) -> String {
    let offset = string.count % 4
    guard offset != 0 else { return string }
    return string.padding(toLength: string.count + 4 - offset, withPad: "=", startingAt: 0)
  }

  public func base64UrlEncodedString() -> String {
    return base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

}
