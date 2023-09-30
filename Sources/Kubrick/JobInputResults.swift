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

    // First try to reduce only non-cancellation errors
    let nonCancellationErrors = errors.filter({ $0 is CancellationError == false })
    if let error = nonCancellationErrors.first {
      if nonCancellationErrors.count == 1 {
        return error
      }
      else {
        return JobExecutionError.multipleInputsFailed(errors)
      }
    }

    // Now try to reduce all errors
    if let error = errors.first {
      if errors.count == 1 {
        return error
      }
      else {
        return JobExecutionError.multipleInputsFailed(errors)
      }
    }

    return nil
  }

}
