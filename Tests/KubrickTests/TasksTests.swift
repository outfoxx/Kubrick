//
//  TasksTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation
@testable import Kubrick
import XCTest


class TasksTests: XCTestCase {

  func test_TrackedTasksCallOnCompleteNoThrow() async throws {

    let cancellationSource = CancellationSource()

    let executed = expectation(description: "Task executed")
    let completed = expectation(description: "onComplete called")

    _ = Task.tracked(cancellationSource: cancellationSource) {
      executed.fulfill()
    } onComplete: {
      completed.fulfill()
    }

    await fulfillment(of: [executed, completed], timeout: 1)
  }

  func test_TrackedTasksCallOnCompleteThrows() async throws {

    let cancellationSource = CancellationSource()

    let executed = expectation(description: "Task executed")
    let completed = expectation(description: "onComplete called")

    _ = Task.tracked(cancellationSource: cancellationSource) {
      executed.fulfill()
      throw URLError(.cancelled)
    } onComplete: {
      completed.fulfill()
    }

    await fulfillment(of: [executed, completed], timeout: 1)
  }

}
