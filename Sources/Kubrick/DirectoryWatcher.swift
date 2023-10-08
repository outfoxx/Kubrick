//
//  DirectoryWatcher.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import Foundation
import OSLog


private let logger = Logger.for(category: "DirectoryWatcher")


class DirectoryWatcher {

  typealias OnShouldWatch = (URL) -> DispatchSource.FileSystemEvent
  typealias OnEvent = (URL, DispatchSource.FileSystemEvent) -> Bool

  struct EntryWatcher {
    var url: URL
    var handle: FileHandle
    var source: DispatchSourceFileSystemObject

    init(url: URL, handle: FileHandle, source: DispatchSourceFileSystemObject) {
      self.url = url
      self.handle = handle
      self.source = source
    }

    func stop() {
      source.cancel()
    }
  }

  let directoryURL: URL
  private let directoryHandle: FileHandle
  private let queue: DispatchQueue

  private var source: DispatchSourceFileSystemObject?
  private var entryWatchers: [UInt64: EntryWatcher] = [:]

  init(url: URL) throws {
    self.directoryURL = url
    self.directoryHandle = try FileHandle(forEventsOnly: url)
    self.queue = DispatchQueue(label: "Directory Watcher", qos: .utility, attributes: [])
  }

  deinit {
    stop()
  }

  func start(onShouldWatch: @escaping OnShouldWatch, onEvent: @escaping OnEvent) async {
    stop()

    await withCheckedContinuation { continuation in

      logger.jobTrace { $0.trace("Watching: url=\(self.directoryURL, privacy: .public), events=write") }

      let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: directoryHandle.fileDescriptor,
                                                             eventMask: [.write],
                                                             queue: queue)

      source.setRegistrationHandler { [weak self] in
        self?.updateEntryWatchers(onShouldWatch: onShouldWatch, onEvent: onEvent)
        continuation.resume()
      }

      source.setEventHandler { [weak self] in
        guard let self else { return }

        logger.jobTrace { $0.trace("Reporting: url=\(self.directoryURL, privacy: .public), events=write") }

        self.updateEntryWatchers(onShouldWatch: onShouldWatch, onEvent: onEvent)
      }

      source.setCancelHandler {
        try? self.directoryHandle.close()
      }

      source.activate()

      self.source = source
    }
  }

  func stop() {
    entryWatchers.forEach { $0.value.stop() }
    entryWatchers.removeAll()

    source?.cancel()
    self.source = nil

    queue.sync(flags: .barrier) {}
  }

  func updateEntryWatchers(onShouldWatch: @escaping OnShouldWatch, onEvent: @escaping OnEvent) {
    do {
      let entryURLs =
        try FileManager.default.subpathsOfDirectory(atPath: directoryURL.path)
          .map { URL(fileURLWithPath: "\(directoryURL.path)/\($0)") }

      let entryIdURLs: [(UInt64, URL)] = entryURLs.compactMap { entryURL in
        guard
          let fileID = try? FileManager.default.attributesOfItem(atPath: entryURL.path)[.systemFileNumber] as? UInt64
        else {
          return nil
        }
        return (fileID, entryURL)
      }

      let entryIdMap = Dictionary(entryIdURLs, uniquingKeysWith: { f, s in f })
      let entryIds = Set(entryIdMap.keys)

      let watchingIds = Set(entryWatchers.keys)

      let deletedIds = watchingIds.subtracting(entryIds)
      let createdIds = entryIds.subtracting(watchingIds)

      for deletedId in deletedIds {
        guard let entryWatcher = entryWatchers[deletedId] else { continue }
        logger.jobTrace { $0.trace("Removing deleted entry: url=\(entryWatcher.url, privacy: .public)") }
        entryWatchers.removeValue(forKey: deletedId)?.stop()
      }

      for createdId in createdIds {

        guard let createdURL = entryIdMap[createdId] else { return }

        let entryWatchEvents = onShouldWatch(createdURL)
        guard !entryWatchEvents.isEmpty else {
          continue
        }

        logger.jobTrace {
          $0.trace("Watching: url=\(createdURL, privacy: .public), events=\(entryWatchEvents, privacy: .public)")
        }

        do {
          let entryHandle = try FileHandle(forEventsOnly: createdURL)
          let entrySource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: entryHandle.fileDescriptor,
                                                                      eventMask: entryWatchEvents,
                                                                      queue: queue)
          entrySource.setRegistrationHandler {

            logger.jobTrace { $0.trace("Registered: url=\(createdURL), events=\(entryWatchEvents)") }

            self.updateEntryWatchers(onShouldWatch: onShouldWatch, onEvent: onEvent)
          }

          entrySource.setEventHandler {

            let event = entrySource.data
            
            logger.jobTrace { $0.trace("Reporting: url=\(createdURL), events=\(event)") }

            self.updateEntryWatchers(onShouldWatch: onShouldWatch, onEvent: onEvent)

            if onEvent(createdURL, event) == false {
              self.entryWatchers[createdId]?.stop()
            }
          }

          entrySource.setCancelHandler {
            try? entryHandle.close()
          }

          entrySource.activate()

          let entryWatcher = EntryWatcher(url: createdURL, handle: entryHandle, source: entrySource)

          entryWatchers[createdId] = entryWatcher
        }
        catch {
          logger.error("Failed to setup entry watcher: error=\(error, privacy: .public)")
        }
      }
    }
    catch {
      logger.error("Error updating entry watchers: error=\(error, privacy: .public)")
    }

  }
}

extension DispatchSource.FileSystemEvent: CustomStringConvertible {

  public var description: String {    
    var results: [String] = []
    if contains(.attrib) {
      results.append("attrib")
    }
    if contains(.delete) {
      results.append("delete")
    }
    if contains(.extend) {
      results.append("extend")
    }
    if contains(.funlock) {
      results.append("funlock")
    }
    if contains(.link) {
      results.append("link")
    }
    if contains(.rename) {
      results.append("rename")
    }
    if contains(.revoke) {
      results.append("revoke")
    }
    if contains(.write) {
      results.append("write")
    }
    return results.joined(separator: ",")
  }

}
