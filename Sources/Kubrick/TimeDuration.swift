//
//  TimeDuration.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public struct TimeDuration: Equatable, Hashable, Codable, Sendable {

  public var nanoseconds: Int64

  public init(nanoseconds: Int64 = 0) {
    self.nanoseconds = nanoseconds
  }

  public init(nanoseconds: Int) {
    self.init(nanoseconds: Int64(nanoseconds))
  }

  public static func seconds(_ seconds: TimeInterval) -> Self {
    return TimeDuration(nanoseconds: Int64(seconds * 1_000_000_000))
  }

  public static func seconds<I: BinaryInteger>(_ totalSeconds: I) -> Self {
    return TimeDuration(nanoseconds: Int64(totalSeconds) * 1_000_000_000)
  }

  public static func milliseconds<I: BinaryInteger>(_ totalMilliseconds: I) -> Self {
    return TimeDuration(nanoseconds: Int64(totalMilliseconds) * 1_000_000)
  }

  public static func microseconds<I: BinaryInteger>(_ totalMicroseconds: I) -> Self {
    return TimeDuration(nanoseconds: Int64(totalMicroseconds) * 1_000)
  }

  public static func nanoseconds<I: BinaryInteger>(_ totalNanoseconds: I) -> Self {
    return TimeDuration(nanoseconds: Int64(totalNanoseconds))
  }

}


public extension TimeDuration {

  var timeInterval: TimeInterval {
    return TimeInterval(nanoseconds) / 1_000_000_000
  }

  var dateAfterNow: Date {
    dateAfter(date: Date())
  }

  func dateAfter(date: Date) -> Date {
    date.addingTimeInterval(timeInterval)
  }

}


extension TimeDuration: Comparable {

  public static func <(lhs: Self, rhs: Self) -> Bool {
    return lhs.nanoseconds < rhs.nanoseconds
  }

}

extension TimeDuration: AdditiveArithmetic {

  public static let zero = TimeDuration()

  public static func + (lhs: TimeDuration, rhs: TimeDuration) -> TimeDuration {
    TimeDuration(nanoseconds: lhs.nanoseconds + rhs.nanoseconds)
  }

  public static func - (lhs: TimeDuration, rhs: TimeDuration) -> TimeDuration {
    TimeDuration(nanoseconds: lhs.nanoseconds - rhs.nanoseconds)
  }

}


extension TimeDuration {

  public static func * <I: BinaryInteger>(lhs: TimeDuration, rhs: I) -> TimeDuration {
    TimeDuration(nanoseconds: lhs.nanoseconds * Int64(rhs))
  }

  public static func / <I: BinaryInteger>(lhs: TimeDuration, rhs: I) -> TimeDuration {
    TimeDuration(nanoseconds: lhs.nanoseconds / Int64(rhs))
  }

}

extension TimeDuration: JobHashable {}
