//
//  JobEnvironment.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public protocol JobEnvironmentKey<Value> {
  associatedtype Value

  static var type: Value.Type { get }
}


public struct JobEnvironment {

  static let current = JobEnvironment()

}
