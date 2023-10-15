//
//  JobInject.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


@propertyWrapper
public struct JobInject<Dependency> {

  typealias Key = JobInjectKey<Dependency>

  let key: Key

  public init(tags: [String] = []) {
    key = Key(tags: tags)
  }

  public init(tags: String...) {
    self.init(tags: tags)
  }

  public init<Tag: RawRepresentable>(tags: [Tag]) where Tag.RawValue: CustomStringConvertible {
    key = Key(tags: tags)
  }

  public init<Tag: RawRepresentable>(tags: Tag...) where Tag.RawValue: CustomStringConvertible {
    key = Key(tags: tags)
  }

  public var wrappedValue: Dependency {
    get {
      guard let director = JobDirector.currentJobDirector else {
        fatalError("No current JobDirector, must be accessed in the 'execute' method of a Job")
      }
      return director.injected[key]
    }
  }

}


public struct JobInjectKey<Dependency> {
  
  public var tags: [String]

  public init(tags: [String]) {
    self.tags = tags
  }

  public init<Tag: RawRepresentable>(tags: [Tag]) where Tag.RawValue: CustomStringConvertible {
    self.tags = tags.map { $0.rawValue.description }
  }

}


extension JobInjectKey: CustomStringConvertible {

  public var description: String {
    return "\(String(describing: Dependency.self))#\(tags.joined(separator: ","))"
  }

}


public class JobInjectValues {

  public var values: [String: Any]

  public init(values: [String : Any] = [:]) {
    self.values = values
  }

  public func provide<Dependency>(
    _ value: Dependency,
    tags: [String] = [],
    forType type: Dependency.Type
  ) {
    self[type, tags: tags] = value
  }

  public func provide<Dependency>(
    _ value: Dependency,
    tags: String...,
    forType type: Dependency.Type = Dependency.self
  ) {
    provide(value, tags: tags, forType: type)
  }

  public func provide<Dependency, Tag: RawRepresentable>(
    _ value: Dependency,
    tags: [Tag] = [],
    forType type: Dependency.Type = Dependency.self
  ) where Tag.RawValue: CustomStringConvertible {
    self[type, tags: tags] = value
  }

  public func provide<Dependency, Tag: RawRepresentable>(
    _ value: Dependency,
    tags: Tag...,
    forType type: Dependency.Type = Dependency.self
  ) where Tag.RawValue: CustomStringConvertible {
    self[type, tags: tags] = value
  }

  public subscript<Dependency>(_ type: Dependency.Type, tags tags: [String] = []) -> Dependency {
    get { self[JobInjectKey(tags: tags)] }
    set { self[JobInjectKey(tags: tags)] = newValue }
  }

  public subscript<Dependency>(_ type: Dependency.Type, tags tags: String...) -> Dependency {
    get { self[JobInjectKey(tags: tags)] }
    set { self[JobInjectKey(tags: tags)] = newValue }
  }

  public subscript<Dependency, Tag: RawRepresentable>(_ type: Dependency.Type, tags tags: [Tag]) -> Dependency
  where Tag.RawValue: CustomStringConvertible {
    get { self[JobInjectKey(tags: tags)] }
    set { self[JobInjectKey(tags: tags)] = newValue }
  }

  public subscript<Dependency, Tag: RawRepresentable>(_ type: Dependency.Type, tags tags: Tag...) -> Dependency
  where Tag.RawValue: CustomStringConvertible {
    get { self[JobInjectKey(tags: tags)] }
    set { self[JobInjectKey(tags: tags)] = newValue }
  }

  public subscript<Dependency>(_ key: JobInjectKey<Dependency>) -> Dependency {
    get {
      guard let rawValue = values[key.description] else {
        fatalError("No value configured for injection key '\(key)'")
      }
      guard let value = rawValue as? Dependency else {
        fatalError(
          """
          Incorrect value configured for injection key '\(key)', \
          expected '\(Dependency.self)' but found '\(type(of: rawValue))'
          """
        )
      }
      return value
    }
    set {
      values[key.description] = newValue
    }
  }

  public func stop() async {
    await withTaskGroup(of: Void.self) { group in
      for managable in values.values.compactMap({ $0 as? JobInjectManagable }) {
        group.addTask {
          await managable.stop()
        }
      }

      for await _ in group {}
    }
  }

}
