//
//  JobTransferError.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


public enum JobTransferError: Error, Codable {
  case transferToPrincipalDirector
}


extension ExecuteResult {

  var isTransfer: Bool {
    guard
      case .failure(let error) = self,
      let txError = error as? JobTransferError,
      txError == .transferToPrincipalDirector
    else {
      return false
    }
    return true
  }

}
