//
//  Locker.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation

let fname = ProcessInfo().arguments[1]

guard let handle = FileHandle(forReadingAtPath: fname) else {
  print("cannot open file \(fname)")
  exit(1)
}

print("locking \(fname)")
if flock(handle.fileDescriptor, LOCK_EX) != 0 {
  print("lock failed (\(errno))")
  exit(1)
}

print("sleeping")
Thread.sleep(forTimeInterval: 1)


print("unlocking \(fname)")
if flock(handle.fileDescriptor, LOCK_UN) != 0 {
  print("lock failed (\(errno))")
  exit(1)
}
