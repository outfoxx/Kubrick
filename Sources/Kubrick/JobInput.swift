//
//  JobInput.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


@propertyWrapper
public struct JobInput<Value: Codable> {

  public var wrappedValue: Value {
    get { projectedValue.value }
    set { projectedValue.set(value: newValue) }
  }

  public var projectedValue: JobBinding<Value>

  public init(wrappedValue: Value) {
    self.init(projectedValue: .init(wrappedValue))
  }

  public init(projectedValue: JobBinding<Value> = .init()) {
    self.projectedValue = projectedValue
  }

}


extension JobInput: JobInputDescriptor {

  public var reportType: Value.Type { Value.self }

  public func resolve(
    for director: JobDirector,
    submission: JobID
  ) async throws -> (id: UUID, result: JobResult<Value>) {
    return try await projectedValue.resolve(for: director, submission: submission)
  }

}


public extension Job {

  var inputDescriptors: [any JobInputDescriptor] {
    let mirror = Mirror(reflecting: self)
    return mirror.children.compactMap { (_, property) in
      property as? any JobInputDescriptor
    }
  }

}
