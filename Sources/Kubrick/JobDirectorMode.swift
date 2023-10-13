//
//  JobDirectorMode.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum JobDirectorMode {
  case principal
  case assistant(name: String)

  public var isPrincipal: Bool {
    guard case .principal = self else {
      return false
    }
    return true
  }

  public var isAssistant: Bool {
    guard case .assistant = self else {
      return false
    }
    return true
  }
}
