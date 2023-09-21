//
//  BatchJob.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "BatchJob")


public struct BatchJob<Key: JobValue & Hashable, ElementJobValue: JobValue>: Job {

  public typealias JobElement = any Job
  public typealias Value = [Key: ElementJobValue]

  let jobs: [UUID: (Key, JobElement)]

  public init<S: Sequence<Key>>(_ keys: S, @JobBuilder<ElementJobValue> block: (S.Element) -> JobElement) {
    self.jobs = Dictionary(uniqueKeysWithValues: keys.map { (UUID(), ($0, block($0))) })
  }

  public init<V, S: Sequence<(key: Key, value: V)>>(_ items: S, @JobBuilder<ElementJobValue> block: (Key, V) -> JobElement) {
    self.jobs = Dictionary(uniqueKeysWithValues: items.map { k, v in (UUID(), (k, block(k, v))) })
  }

  public var inputDescriptors: [any JobInputDescriptor] {

    func descriptor(id: UUID, job: some Job) -> any JobInputDescriptor {
      AdHocJobInputDescriptor(id: id, job: job)
    }

    return jobs.map { id, element in descriptor(id: id, job: element.1) }
  }

  public func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async -> JobResult<Value> {
    do {
      let results = try jobs.map { (id, element) in
        let (key, _) = element

        guard let inputResult = inputResults[id] else {
          throw JobError.invariantViolation(.inputResultMissing)
        }

        guard let inputValue = try inputResult.get() as? ElementJobValue else {
          throw JobError.invariantViolation(.inputResultInvalid)
        }

        return (key, inputValue)
      }
      return .success(Dictionary(uniqueKeysWithValues: results))
    }
    catch {
      return .failure(error)
    }
  }

}

