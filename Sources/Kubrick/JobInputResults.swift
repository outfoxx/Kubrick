//
//  JobInputResults.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public typealias JobInputResults = [UUID: AnyJobInputResult]


extension JobInputResults {

  var failure: Error? {
    let errors = values.compactMap { inputResult -> (any Error)? in
      guard case .failure(let error) = inputResult else { return nil }
      return error
    }
    if let error = errors.first {
      if errors.count == 1 {
        return error
      }
      else {
        return JobError.multipleInputsFailed(errors)
      }
    }
    return nil
  }

}
