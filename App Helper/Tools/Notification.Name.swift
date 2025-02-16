//
//  Notification.Name.swift
//  Stand Reminder
//
//  Created by zhaoxin on 2022/9/16.
//

import Foundation

extension Notification.Name {
  static let updateWindow = Notification.Name("updateWindow")
  static let simulatedWindowClose = Notification.Name("simulatedWindowClose")

  static let notificationError = Notification.Name("notificationError")
  static let notificationAuthorizeDenied = Notification.Name("notificationAuthorizeDenied")

  static let hdrStatusChanged = Notification.Name("hdrStatusChanged")

  static let hasBrewUpdates = Notification.Name("hasBrewUpdates")
}
