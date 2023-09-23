//
//  UUIDs.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import CryptoKit
import Foundation

extension UUID {

  init(namespace: UUID, name: Data) {

    var sha1 = Insecure.SHA1()

    var namespace = namespace.uuid
    withUnsafeBytes(of: &namespace) { sha1.update(bufferPointer: $0)  }

    sha1.update(data: name)

    var data = sha1.finalized().subdata(in: 0 ..< 16)

    // Mark as version 5 UUID
    data[6] &= 0x0f
    data[6] |= 0x50
    data[8] &= 0x3f
    data[8] |= 0x80

    self = .init(data: data)
  }

  init(data: Data) {
    precondition(data.count == 16)

    let uuid = data.withUnsafeBytes { srcPtr in
      var uuid = UUID_NULL
      withUnsafeMutableBytes(of: &uuid) { dstPtr in
        dstPtr.copyBytes(from: srcPtr)
      }
      return uuid
    }

    self = .init(uuid: uuid)
  }

}
