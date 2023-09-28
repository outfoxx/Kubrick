//
//  JobBuilderTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@testable import Kubrick
import XCTest


class JobBuilderTests: XCTestCase {

  enum SomeError: Error {
    case something
  }

  struct IntJob: ResultJob {
    func execute() async throws -> Int {
      return Int.random(in: .min ... .max)
    }
  }

  struct OptionalIntJob: ResultJob {
    func execute() async throws -> Int? {
      return nil
    }
  }

  struct OtherIntJob: ResultJob {
    func execute() async throws -> Int {
      return Int.random(in: .min ... .max)
    }
  }

  struct RandomIntJob: ResultJob {
    func execute() async throws -> Int {
      return Int.random(in: .min ... .max)
    }
  }

  func test_JobInputBindNonNilValueToNonOptionalValueInput() {

    do {
      @JobInput var test: Int
      $test.bind(value: 5)

      XCTAssertEqual(_test.boundJobOrValue, "5")
    }

    do {
      @JobInput var test: Int
      test = 10

      XCTAssertEqual(_test.boundJobOrValue, "10")
    }
  }

  func test_JobInputBindNonNilValueToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(value: 5)

      XCTAssertEqual(_test.boundJobOrValue, "Optional(5)")
    }

    do {
      @JobInput var test: Int?
      test = 10

      XCTAssertEqual(_test.boundJobOrValue, "Optional(10)")
    }
  }

  func test_JobInputBindNilValueToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(value: nil)

      XCTAssertEqual(_test.boundJobOrValue, "nil")
    }

    do {
      @JobInput var test: Int?
      test = nil

      XCTAssertEqual(_test.boundJobOrValue, "nil")
    }
  }

  func test_JobInputBindNonNilJobToNonOptionalValueInput() {

    do {
      @JobInput var test: Int
      $test.bind(job: IntJob())

      XCTAssertEqual(_test.boundJobOrValue, "IntJob")
    }

    do {
      @JobInput var test: Int
      $test.bind { IntJob() }

      XCTAssertEqual(_test.boundJobOrValue, "IntJob")
    }
  }

  func test_JobInputBindNonNilJobToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(job: IntJob())

      XCTAssertEqual(_test.boundJobOrValue, "IntJob")
    }

    do {
      @JobInput var test: Int?
      $test.bind { IntJob() }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalJob<Int, IntJob>")
    }
  }

  func test_JobInputBindNilJobToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(job: nil as IntJob?)

      XCTAssertEqual(_test.boundJobOrValue, "nil")
    }

    do {
      @JobInput var test: Int?
      $test.bind { nil as IntJob? }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalJob<Int, IntJob>")
    }
  }

  func test_JobInputBindNonNilOptionalResultJobToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(job: OptionalIntJob())

      XCTAssertEqual(_test.boundJobOrValue, "OptionalIntJob")
    }

    do {
      @JobInput var test: Int?
      $test.bind { OptionalIntJob() }

      XCTAssertEqual(_test.boundJobOrValue, "OptionalIntJob")
    }
  }

  func test_JobInputBindNilOptionalResultJobToOptionalValueInput() {

    do {
      @JobInput var test: Int?
      $test.bind(job: nil as OptionalIntJob?)

      XCTAssertEqual(_test.boundJobOrValue, "nil")
    }

    do {
      @JobInput var test: Int?
      $test.bind { nil as OptionalIntJob? }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalOptionalJob<Int, OptionalIntJob>")
    }
  }

  func test_IfExpression() {

    do {
      @JobInput var test: Int?
      $test.bind { if true { IntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalOptionalJob<Int, _OptionalJob<Int, IntJob>>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if true { OptionalIntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalOptionalJob<Int, OptionalIntJob>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if true { nil as IntJob? } }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalOptionalJob<Int, _OptionalJob<Int, IntJob>>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if true { nil as OptionalIntJob? } }

      XCTAssertEqual(_test.boundJobOrValue, "_OptionalOptionalJob<Int, _OptionalOptionalJob<Int, OptionalIntJob>>")
    }
  }

  func test_IfElseExpression() {

    let decision = true

    do {
      @JobInput var test: Int
      $test.bind { if decision { IntJob() } else { OtherIntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_ConditionalJob<Int, IntJob, OtherIntJob>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if decision { OptionalIntJob() } else { OtherIntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_ConditionalJob<Optional<Int>, OptionalIntJob, _OptionalJob<Int, OtherIntJob>>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if decision { IntJob() } else { OptionalIntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_ConditionalJob<Optional<Int>, _OptionalJob<Int, IntJob>, OptionalIntJob>")
    }

    do {
      @JobInput var test: Int?
      $test.bind { if decision { nil as IntJob? } else { OptionalIntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_ConditionalJob<Optional<Int>, _OptionalJob<Int, IntJob>, OptionalIntJob>")
    }

    do {
      @JobInput var test: Int
      $test.bind { if decision { IntJob() } else { IntJob() } }

      XCTAssertEqual(_test.boundJobOrValue, "_ConditionalJob<Int, IntJob, IntJob>")
    }
  }

  func test_SwitchExpression() {

    let decision = 0

    do {
      @JobInput var test: Int
      $test.bind {
        switch decision {
        case 0: IntJob()
        case 1: OtherIntJob()
        case 2: RandomIntJob()
          // TODO: case 3: throw SomeError.something
        default: fatalError()
        }
      }

      XCTAssertEqual(
        _test.boundJobOrValue,
        """
        _ConditionalJob<Int, \
        _ConditionalJob<Int, IntJob, OtherIntJob>, \
        _ConditionalJob<Int, RandomIntJob, _NeverJob<Int>>\
        >
        """
      )
    }

    do {
      @JobInput var test: Int?
      $test.bind {
        switch decision {
        case 0: nil as IntJob?
        case 1: OptionalIntJob()
        case 2: nil as OptionalIntJob?
          // TODO: case 3: throw SomeError.something
        default: fatalError()
        }
      }

      XCTAssertEqual(
        _test.boundJobOrValue,
        """
        _ConditionalJob<Optional<Int>, \
        _ConditionalJob<Optional<Int>, _OptionalJob<Int, IntJob>, OptionalIntJob>, \
        _ConditionalJob<Optional<Int>, _OptionalOptionalJob<Int, OptionalIntJob>, _NeverJob<Optional<Int>>>\
        >
        """
      )
    }
  }

}

extension JobBinding where Value: JobValue {

  var boundJob: (any Job.Type)? {
    guard case .job(_, let resolver) = state else {
      return nil
    }
    switch resolver {
    case let pass as PassthroughJobResolver<Int>:
      return type(of: pass.job)
    case let pass as PassthroughJobResolver<Int?>:
      return type(of: pass.job)
    case let opt as OptionalJobResolver<Int>:
      return type(of: opt.job)
    case let opt as OptionalJobResolver<Int?>:
      return type(of: opt.job)
    default:
      return nil
    }
  }

  var boundValue: Value? {
    guard case .constant(_, let value) = state else {
      return nil
    }
    return value
  }

}

extension JobInput where Value: JobValue {

  var boundJobOrValue: String {
    if let boundJob = projectedValue.boundJob {
      return String(describing: boundJob).replacingOccurrences(of: "KubrickTests.JobBuilderTests.", with: "")
    }
    if let boundValue = projectedValue.boundValue {
      return String(describing: boundValue)
    }
    return ""
  }

}
