//
//  UserNotificationJobManager.swift
//  Kubrick
//
//  Copyright © 2023 Outfox, inc.
//
//
//  Distributed under the MIT License, See LICENSE for details.
//

import AsyncObjects
import Foundation
import UserNotifications
import OSLog


private let logger = Logger.for(category: "UserNotifications")


public actor UserNotificationJobManager {

  class Delegate: NSObject, UNUserNotificationCenterDelegate {

    weak var owner: UserNotificationJobManager?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
      guard let owner else { return }

      do {
        guard let (_, jobInfo) = try await owner.findJobInfo(notification: response.notification) else {
          // TODO: log
          return
        }

        Task { await jobInfo.future.fulfill(producing: response) }
      }
      catch {
        // TODO: log
      }
    }

  }

  struct UserNotificationJobInfo {
    let future: Future<UNNotificationResponse, Error>
  }

  private let director: JobDirector
  private let notificationJobInfoCache = RegisterCache<JobKey, UserNotificationJobInfo>()

  public init(director: JobDirector) {
    self.director = director
  }

  public func show(
    content: UNNotificationContent,
    trigger: UNNotificationTrigger? = nil
  ) async throws -> UNNotificationResponse {

    guard let jobKey = JobDirector.currentJobKey else {
      fatalError("No current job key")
    }

    let extJobKey = ExternalJobKey(directorId: director.id, jobKey: jobKey)

    let request = UNNotificationRequest(identifier: extJobKey.value,
                                        content: content,
                                        trigger: trigger)

    let jobInfo = try await notificationJobInfoCache.register(for: jobKey) {

      try await UNUserNotificationCenter.current().add(request)

      return UserNotificationJobInfo(future: Future())
    }

    return try await withTaskCancellationHandler {
      try await jobInfo.future.get()
    } onCancel: {
      Task { await jobInfo.future.fulfill(throwing: CancellationError()) }
    }
  }

  private func findJobInfo(notification: UNNotification) async throws -> (JobKey, UserNotificationJobInfo)? {
    guard
      let externalJobKey = ExternalJobKey(string: notification.request.identifier),
      externalJobKey.directorId == director.id
    else {
      return nil
    }
    return (externalJobKey.jobKey, try await notificationJobInfoCache.valueWhenAvailable(for: externalJobKey.jobKey))
  }

}


public struct UserNotificationJob<ResultValue: JobValue>: ResultJob {

  public typealias Transform = (UNNotificationResponse) async throws -> ResultValue

  let content: UNNotificationContent
  let transform: Transform

  @JobInject private var manager: UserNotificationJobManager

  public init(content: UNNotificationContent, transform: @escaping Transform) {
    self.content = content
    self.transform = transform
  }

  public func execute() async throws -> ResultValue {

    let response = try await manager.show(content: content)

    return try await transform(response)
  }

}
