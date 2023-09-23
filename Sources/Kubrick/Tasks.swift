//
//  Tasks.swift
//  
//
//  Created by Kevin Wooten on 9/22/23.
//

import Foundation


extension Task where Success == Never, Failure == Never {

  static func sleep(seconds: TimeInterval) async throws {
    try await sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  static func sleep(until date: Date) async throws {

    let duration = max(date.timeIntervalSinceReferenceDate - Date.now.timeIntervalSinceReferenceDate, 0)

    try await Task.sleep(seconds: duration)
  }

}
