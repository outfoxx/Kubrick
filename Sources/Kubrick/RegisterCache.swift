//
//  RegisterCache.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation


public protocol RegisterCacheStore<Key, Value> {
  associatedtype Key: Hashable
  associatedtype Value

  func value(forKey key: Key) async throws -> Value?
  func updateValue(_ value: Value, forKey key: Key) async throws
  func removeValue(forKey key: Key) async throws

}


public actor RegisterCache<Key: Hashable, Value> {

  public struct NullStore: RegisterCacheStore {

    public init() {}

    public func value(forKey key: Key) async throws -> Value? { nil }

    public func updateValue(_ value: Value, forKey key: Key) async throws {}

    public func removeValue(forKey key: Key) async throws {}

    public func removeValues(forKeys keys: Set<Key>) async throws {}

  }

  typealias Future = AsyncObjects.Future<Value, Error>

  enum Entry {
    case available(Future)
    case waiting(Future)

    var future: Future {
      switch self {
      case .available(let future), .waiting(let future):
        return future
      }
    }
  }

  private var state: [Key: Entry] = [:]
  private let store: any RegisterCacheStore<Key, Value>

  public init(store: any RegisterCacheStore<Key, Value> = NullStore()) {
    self.store = store
  }

  /// Registers a value with the cache, if none is already registered, and initializes it
  /// to the value returned by `initializer`.
  ///
  /// - Parameters:
  ///   - key: Cache key to register value for.
  ///   - initializer: Initializer to run when the value is not present and needs to be initialized.
  /// - Returns: The previously registered, or newly initialized, value associated with `key`.
  ///
  public func register(for key: Key, initializer: @escaping () async throws -> Value) async throws -> Value {

    switch state[key] {
    case .none:
      let future = Future()
      state[key] = .available(future)
      return try await initialize(future: future)

    case .waiting(let future):
      state[key] = .available(future)
      return try await initialize(future: future)

    case .available(let future):
      return try await future.get()
    }

    func initialize(future: Future) async throws -> Value {
      let initTask = Task {
        do {

          let value: Value
          if let current = try await store.value(forKey: key) {
            value = current
          }
          else {

            value = try await initializer()

            try await store.updateValue(value, forKey: key)
          }

          await future.fulfill(producing: value)

        }
        catch {

          await future.fulfill(throwing: error)
        }
      }

      return try await withTaskCancellationHandler {
        try await future.get()
      } onCancel: {
        Task {
          try? await deregister(for: key)
          initTask.cancel()
        }
      }
    }
  }

  public func deregister(for key: Key) async throws {
    try await store.removeValue(forKey: key)
    state.removeValue(forKey: key)
  }

  /// Returns the value associated with the given `key`, waiting indefinitely until `key`
  /// is registered and available.
  ///
  /// - Parameter key: Cache key to wait upon.
  /// - Returns: Value associate with `key` when it becomes available.
  ///
  public func valueWhenAvailable(for key: Key) async throws -> Value {
    
    return try await state[key, default: .waiting(Future())].future.get()
  }

  /// If the given `key` is registered, returns the value associated with the `key` waiting
  /// indefinitely for it to become avaialble.
  ///
  /// - Parameter key: Cache key check and wait upon.
  /// - Returns: Value associated with `key`, if registered, when it becomes available.
  ///
  public func valueIfRegistered(for key: Key) async throws -> Value? {
    
    return try await state[key]?.future.get()
  }

}
