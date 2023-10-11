//
//  DirectoryWatcherTests.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
@testable import Kubrick
import OSLog
import XCTest


class DirectoryWatcherTests: XCTestCase {

  var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UniqueID.generateString())
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: dir)
  }

  func test_EntryAttribReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .attrib

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryDeleteReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .delete

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try FileManager.default.removeItem(at: fileURL)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryExtendReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .extend

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try String("hello watcher").data(using: .utf8)?.write(to: fileURL)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryFunlockReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .funlock

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all, .funlock]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.lock()
    try handle.unlock()

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryFUnlockReportedForOtherProcesses() async throws {

    func compileLocker() async throws -> URL {
      print("⚙️ Compiling Locker Tool")

      let pkgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

      let lockerSourceURL = pkgDir.appendingPathComponent("Tests/Tools/Locker.swift")
      let lockerURL = pkgDir.appendingPathComponent(".build/Tools/Locker")

      try XCTSkipIf(try lockerSourceURL.checkResourceIsReachable())

      try FileManager.default.createDirectory(at: lockerURL.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)

      try await shell("swiftc", lockerSourceURL.path, "-o", lockerURL.path)

      return lockerURL
    }

    let lockerURL = try await compileLocker()

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .funlock

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all, .funlock]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try await shell(lockerURL.path, fileURL.path)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryLinkReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .link

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try FileManager.default.linkItem(at: fileURL, to: dir.appendingPathComponent(UniqueID.generateString()))

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryRenameReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName1 = UniqueID.generateString()
    let fileName2 = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .rename

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if fileName1 == url.lastPathComponent {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if fileName1 == url.lastPathComponent && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL1 = dir.appendingPathComponent(fileName1)
    let fileURL2 = dir.appendingPathComponent(fileName2)
    try Data().write(to: fileURL1)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try FileManager.default.moveItem(at: fileURL1, to: fileURL2)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EntryWriteReported() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .write

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [.all]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event.contains(fileEvent) {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try String("hello watcher").data(using: .utf8)?.write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try String("hello watcher").data(using: .utf8)?.write(to: fileURL)

    await fulfillment(of: [eventEx], timeout: 3)
  }

  func test_EventsFiltered() async throws {

    let shouldWatchEx = expectation(description: "Should Watch")
    let eventEx = expectation(description: "Event Reported")
    eventEx.isInverted = true

    let fileName = UniqueID.generateString()
    let fileEvent: DispatchSource.FileSystemEvent = .write

    let watch = try DirectoryWatcher(url: dir)
    defer { watch.stop() }

    await watch.start { url in
      if url.lastPathComponent == fileName {
        shouldWatchEx.fulfill()
        return [fileEvent]
      }
      return []
    } onEvent: { url, event in
      if url.lastPathComponent == fileName && event != [] {
        eventEx.fulfill()
        return false
      }
      return true
    }

    let fileURL = dir.appendingPathComponent(fileName)
    try Data().write(to: fileURL)

    await fulfillment(of: [shouldWatchEx], timeout: 3)

    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

    await fulfillment(of: [eventEx], timeout: 1)
  }

}


func shell(_ args: String...) async throws -> Void {

  enum Error: Swift.Error {
    case executeFailed(String)
  }

  let command = args.joined(separator: " ")

  let p = Process()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          p.executableURL = URL(fileURLWithPath: "/bin/zsh")
          p.arguments = ["-c", command]
          p.standardOutput = FileHandle.standardOutput
          try p.run()
          p.waitUntilExit()
          if p.terminationStatus != 0 {
            cont.resume(throwing: Error.executeFailed(command))
          }
          else {
            cont.resume()
          }
        }
        catch {
          cont.resume(throwing: error)
        }
      }
    }
  } onCancel: {
    p.terminate()
  }
}
