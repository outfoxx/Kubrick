//
//  Logging.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import OSLog


extension Logger {

  static func `for`(category: String) -> Logger {
    return Logger(subsystem: "io.outfoxx.kubrick", category: category)
  }

}
