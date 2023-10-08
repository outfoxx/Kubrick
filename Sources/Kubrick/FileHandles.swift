//
//  FileHandles.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation


enum FileLockType {
  case shared
  case exclusive

  var posix: Int32 {
    switch self {
    case .shared: return LOCK_SH
    case .exclusive: return LOCK_EX
    }
  }
}


extension FileHandle {

  convenience init(forEventsOnly url: URL) throws {
    let fd = open(url.path, O_EVTONLY)
    if fd == -1 {
      switch errno {
      case ENOENT:
        throw CocoaError(.fileNoSuchFile, userInfo: [
          NSURLErrorKey: url,
        ])
      case EACCES:
        throw CocoaError(.fileReadNoPermission, userInfo: [
          NSURLErrorKey: url,
        ])
      default:
        throw CocoaError(.fileReadUnknown, userInfo: [
          NSURLErrorKey: url,
          NSUnderlyingErrorKey: POSIXError.Code(rawValue: errno).map { POSIXError($0) } as Any
        ])
      }
    }
    self.init(fileDescriptor: fd)
  }

  convenience init(forDirectory url: URL) throws {
    let fd = open(url.path, O_RDONLY | O_DIRECTORY)
    if fd == -1 {
      switch errno {
      case ENOENT:
        throw CocoaError(.fileNoSuchFile, userInfo: [
          NSURLErrorKey: url,
        ])
      case EACCES:
        throw CocoaError(.fileReadNoPermission, userInfo: [
          NSURLErrorKey: url,
        ])
      default:
        throw CocoaError(.fileReadUnknown, userInfo: [
          NSURLErrorKey: url,
          NSUnderlyingErrorKey: POSIXError.Code(rawValue: errno).map { POSIXError($0) } as Any
        ])
      }
    }
    self.init(fileDescriptor: fd)
  }

  func lock(type: FileLockType = .exclusive) throws {
    if flock(fileDescriptor, type.posix) != 0 {
      try throwErrno()
    }
  }

  func tryLock(type: FileLockType = .exclusive) throws -> Bool {
    switch flock(fileDescriptor, LOCK_NB | type.posix) {
    case 0:
      return true
    case EWOULDBLOCK:
      return false
    default:
      try throwErrno()
    }
  }

  func unlock() throws {
    if flock(fileDescriptor, LOCK_UN) != 0 {
      try throwErrno()
    }
  }

  func throwErrno() throws -> Never {
    throw POSIXError(.init(rawValue: errno) ?? .EIO)
  }

}
