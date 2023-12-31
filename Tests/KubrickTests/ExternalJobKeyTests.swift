//
//  ExternalJobKeyTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation
@testable import Kubrick
import XCTest


class ExternalJobKeyTests: XCTestCase {

  func test_RoundTripWithoutTags() {

    let jobKey = JobKey(id: .generate(), fingerprint: SHA256().finalized(), tags: [])
    let externalJobKey = ExternalJobKey(directorId: .generate(), jobKey: jobKey)

    print(externalJobKey)

    XCTAssertEqual(externalJobKey, ExternalJobKey(string: externalJobKey.value))
  }

  func test_RoundTripWithTags() {

    let jobKey = JobKey(id: .generate(), fingerprint: SHA256().finalized(), tags: ["test-1", "test-2"])
    let externalJobKey = ExternalJobKey(directorId: .generate(), jobKey: jobKey)

    print(externalJobKey)

    XCTAssertEqual(externalJobKey, ExternalJobKey(string: externalJobKey.value))
  }

}
