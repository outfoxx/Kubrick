//
//  JobError.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum JobError: Error {
  
  public enum InvariantViolation {
    case noCurrentInputs
    case inputResultMissing
    case inputResultInvalid
    case inputFailureInvokedWithoutError
    case executeInvokedWithFailedInput
  }

  case invariantViolation(InvariantViolation)
  case multipleInputsFailed([Error])
}
