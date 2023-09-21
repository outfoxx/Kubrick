//
//  InjectTests.swift
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


class InjectTests: XCTestCase {

  func test_SimpleTypeInjectWithoutTags() {

    let values = JobInjectValues()
    values[Int.self] = 10

    XCTAssertEqual(values[Int.self], 10)
  }

  func test_SimpleTypeInjectWithStringTags() {

    let values = JobInjectValues()
    values[Int.self, tags: "test"] = 10

    XCTAssertEqual(values[Int.self, tags: "test"], 10)
  }

  func test_SimpleTypeInjectWithRawValueTags() {

    enum InjectTags: String {
      case test
      case test2
    }

    let values = JobInjectValues()
    values[Int.self, tags: InjectTags.test, InjectTags.test2] = 10

    XCTAssertEqual(values[Int.self, tags: InjectTags.test, InjectTags.test2], 10)
  }

  func test_GenericTypeInjectWithoutTags() {

    struct Generic<Value: Equatable>: Equatable {
      var value: Value
    }

    let values = JobInjectValues()
    values[Generic<Int>.self] = Generic(value: 10)

    XCTAssertEqual(values[Generic<Int>.self], Generic(value: 10))
  }

  func test_GenericTypeInjectWithStringTags() {

    struct Generic<Value: Equatable>: Equatable {
      var value: Value
    }

    let values = JobInjectValues()
    values[Generic<Int>.self, tags: "test"] = Generic(value: 10)

    XCTAssertEqual(values[Generic<Int>.self, tags: "test"], Generic(value: 10))
  }

  func test_GenericTypeInjectWithRawValueTags() {

    enum InjectTags: String {
      case test
      case test2
    }

    struct Generic<Value: Equatable>: Equatable {
      var value: Value
    }

    let values = JobInjectValues()
    values[Generic<Int>.self, tags: InjectTags.test, InjectTags.test2] = Generic(value: 10)

    XCTAssertEqual(values[Generic<Int>.self, tags: InjectTags.test, InjectTags.test2], Generic(value: 10))
  }

}
