//
//  TimeDurationTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import Kubrick
import XCTest


class TimeDurationTests: XCTestCase {

  func test_InitSecondsFromTimeInterval() {

    do {
      let td: TimeDuration = .seconds(1.23456789)

      XCTAssertEqual(td.nanoseconds, 1_234_567_890)
    }

    do {
      let td: TimeDuration = .seconds(-1.23456789)

      XCTAssertEqual(td.nanoseconds, -1_234_567_890)
    }

  }

  func test_InitMilliseconds() {

    do {
      let td: TimeDuration = .milliseconds(1_234)

      XCTAssertEqual(td.nanoseconds, 1_234_000_000)
    }

    do {
      let td: TimeDuration = .milliseconds(-1_234)

      XCTAssertEqual(td.nanoseconds, -1_234_000_000)
    }
  }

  func test_InitMicroseconds() {

    do {
      let td: TimeDuration = .microseconds(1_234_567)

      XCTAssertEqual(td.nanoseconds, 1_234_567_000)
    }

    do {
      let td: TimeDuration = .microseconds(-1_234_567)

      XCTAssertEqual(td.nanoseconds, -1_234_567_000)
    }
  }

  func test_InitNanoseconds() {

    do {
      let td: TimeDuration = .nanoseconds(1_234_567_890)

      XCTAssertEqual(td.nanoseconds, 1_234_567_890)
    }

    do {
      let td: TimeDuration = .nanoseconds(-1_234_567_890)

      XCTAssertEqual(td.nanoseconds, -1_234_567_890)
    }
  }

  func test_Add() {

    let td1: TimeDuration = .seconds(1.234)
    let td2: TimeDuration = .seconds(1.111)

    let td = td1 + td2
    XCTAssertEqual(td.nanoseconds, 2_345_000_000)
  }

  func test_Subtract() {

    let td1: TimeDuration = .seconds(1.234)
    let td2: TimeDuration = .seconds(1.111)

    let td = td1 - td2
    XCTAssertEqual(td.nanoseconds, 123_000_000)
  }

  func test_Multiply() {

    do {
      let td1: TimeDuration = .seconds(1.123)

      let td = td1 * 3
      XCTAssertEqual(td.nanoseconds, 3_369_000_000)
    }

    do {
      let td1: TimeDuration = .seconds(1.123)

      let td = td1 * -2
      XCTAssertEqual(td.nanoseconds, -2_246_000_000)
    }
  }

  func test_Division() {

    let td1: TimeDuration = .seconds(2.468)

    let td = td1 / 2
    XCTAssertEqual(td.nanoseconds, 1_234_000_000)
  }

  func test_TimeInterval() {

    let td: TimeDuration = .seconds(1.234567890)

    XCTAssertEqual(td.timeInterval, 1.234567890)
  }

  func test_DateAfterNow() {

    let td: TimeDuration = .seconds(1.234567890)

    let now = Date()

    XCTAssertEqual(
      td.dateAfter(date: now).timeIntervalSinceReferenceDate,
      now.addingTimeInterval(1.234567890).timeIntervalSinceReferenceDate
    )
  }

}
