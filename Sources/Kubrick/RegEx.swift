//
//  RegEx.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation

extension NSRegularExpression {
  convenience init(_ pattern: String) {
    do {
      try self.init(pattern: pattern)
    } catch {
      preconditionFailure("Illegal regular expression: \(pattern).")
    }
  }
}

extension NSRegularExpression {
  func matches(_ string: String, groupNames: Set<String> = []) -> [String: Substring]? {
    let range = NSRange(location: 0, length: string.count)
    guard
      let match = firstMatch(in: string, options: [], range: range),
      match.range == range
    else {
      return nil
    }
    let groups = groupNames.map { ($0, match.range(withName: $0)) }.map { key, range in
      guard range.lowerBound != .max else {
        return (key, Substring(""))
      }
      let startIdx = string.index(string.startIndex, offsetBy: range.lowerBound)
      let endIdx = string.index(startIdx, offsetBy: range.length)
      return (key, string[startIdx ..< endIdx])
    }
    return Dictionary(uniqueKeysWithValues: groups)
  }
}
