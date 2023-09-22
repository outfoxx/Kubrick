//
//  UniqueId.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@_exported import FriendlyId


public typealias UniqueID = FriendlyId.Id


public extension UniqueID {

  static func generate() -> UniqueID { UniqueID() }
  static func generateString() -> String { generate().description }

}

extension UniqueID {

  init(data: Data) {
    self = Self(uuid: UUID(data: data))
  }

}
