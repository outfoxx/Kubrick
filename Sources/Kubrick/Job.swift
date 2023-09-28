//
//  Job.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import PotentCodables
import Foundation


public protocol Job<Value> {
  
  associatedtype Value: JobValue

  var inputDescriptors: [any JobInputDescriptor] { get }

  func execute(
    as jobKey: JobKey,
    with inputResults: JobInputResults,
    for director: JobDirector
  ) async throws -> JobResult<Value>

}


public extension Job {

  var inputDescriptors: [any JobInputDescriptor] {
    let mirror = Mirror(reflecting: self)
    return mirror.children.compactMap { (_, property) in
      property as? any JobInputDescriptor
    }
  }

}
