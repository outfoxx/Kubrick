//
//  JobEnvironmentValue.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


@propertyWrapper
public struct JobEnvironmentValue<Value> {

  let keyPath: KeyPath<JobEnvironment, Value>

  public var wrappedValue: Value {
    get {
      JobEnvironment.current[keyPath: keyPath]
    }
  }

  public init(_ keyPath: KeyPath<JobEnvironment, Value>) {
    self.keyPath = keyPath
  }

}
