//
//  Tasks.swift
//  
//
//  Created by Kevin Wooten on 9/22/23.
//

import AsyncObjects
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


extension Task where Success == Void, Failure == Never {

  static func tracked<FutureSuccess>(
    priority: TaskPriority? = nil,
    cancellationSource: CancellationSource,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    operation: @Sendable @escaping () async throws -> FutureSuccess,
    onComplete: @Sendable @escaping () async -> Void = {}
  ) -> Future<FutureSuccess, Error> {
    let future = Future<FutureSuccess, Error>()

    detached(priority: priority, cancellationSource: cancellationSource, file: file, function: function, line: line) {
      do {
        await future.fulfill(producing: try await operation())
      }
      catch {
        await future.fulfill(throwing: error)
        await onComplete()
      }
    }

    return future
  }

}
