//
//  AssistantsWatcher.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "AssistantsWatcher")


class AssistantsWatcher {

  let assistantsLocation: URL
  var watcher: DirectoryWatcher

  init(assistantsLocation: URL) throws {
    self.assistantsLocation = assistantsLocation.resolvingSymlinksInPath().standardized
    self.watcher = try DirectoryWatcher(url: assistantsLocation)
  }

  func start(onUnlockedJob: @escaping (URL) -> Void) async throws {
    await watcher.start { [self] entryURL in

      if isAssistantDirectory(url: entryURL) || isAssistantJobsDirectory(url: entryURL) {        
        return [.write]
      }
      else if isJobPackage(url: entryURL) {
        return [.funlock]
      }

      return []

    } onEvent: { [self] entryURL, event in

      if isJobPackage(url: entryURL) {
        onUnlockedJob(entryURL)
        return false
      }

      return true
    }

    try FileManager.default.subpathsOfDirectory(atPath: assistantsLocation.path)
      .map { URL(fileURLWithPath: "\(assistantsLocation.path)/\($0)") }
      .filter { isJobPackage(url: $0) }
      .forEach { jobURL in
        do {
          let jobHandle = try FileHandle(forDirectory: jobURL)
          defer { try? jobHandle.unlock() }
          if try jobHandle.tryLock() {
            onUnlockedJob(jobURL)
          }
        }
        catch {
          logger.error("Checking existing job failed: error=\(error, privacy: .public)")
        }
      }
  }

  func stop() {
    watcher.stop()
  }

  func isAssistantDirectory(url: URL) -> Bool {
    let parentDir = url.deletingLastPathComponent()
    return parentDir.resolvingSymlinksInPath().standardized == assistantsLocation
  }

  func isAssistantJobsDirectory(url: URL) -> Bool {
    guard url.lastPathComponent == "jobs" else {
      return false
    }
    let grandparentDir = url.deletingLastPathComponent().deletingLastPathComponent()
    return grandparentDir.resolvingSymlinksInPath().standardized == assistantsLocation
  }

  func isJobPackage(url: URL) -> Bool {
    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true) ?? false
    return isDir && url.pathExtension == JobDirectorStore.EntryKind.jobPackage.description
  }

}
