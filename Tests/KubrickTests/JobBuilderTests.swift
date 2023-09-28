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
import Kubrick
import XCTest


class JobBuilderTests: XCTestCase {

  func test_JobInputBind() {

    struct RandomJob: ResultJob {
      func execute() async throws -> Int {
        return Int.random(in: .min ... .max)
      }
    }

    struct MainJob: SubmittableJob {

      @JobInput var test: Int

      init() {
        $test.bind {
          RandomJob()
        }
      }

      func execute() async {}
      init(data: Data) throws { self.init() }
      func encode() throws -> Data { Data() }
    }

  }

  func test_JobInputBindOptional() {

    struct RandomJob: ResultJob {
      func execute() async throws -> Int {
        return Int.random(in: .min ... .max)
      }
    }

    struct MainJob: SubmittableJob {

      @JobInput var test: Int?

      init() {
        $test.bind {
          RandomJob()
        }
      }

      func execute() async {}
      init(data: Data) throws { self.init() }
      func encode() throws -> Data { Data() }
    }

  }

  func test_IfExpression() {

    struct TrueJob: ResultJob {
      func execute() async throws -> Bool {
        return true
      }
    }

    struct FalseJob: ResultJob {
      func execute() async throws -> Bool {
        return false
      }
    }

//    @JobBuilder<Bool>
//    func build(_ value: Bool) -> some Job<Bool> {
//      if value {
//        TrueJob()
//      }
//      else {
//        FalseJob()
//      }
//    }
//
//    XCTAssertTrue(build(true) is TrueJob)
//    XCTAssertTrue(build(true) is FalseJob)
  }

}
