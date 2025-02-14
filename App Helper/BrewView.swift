//
//  BrewView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/2/8.
//

import SwiftUI

struct BrewView: View {
  @State private var hasUpdate = false
  @State private var terminalRunning = false
  @State private var showBrewUpgadeAlert = false
  @State private var brewUpgradeResult: String? = nil
  @State private var updateAppList: [String] = []

  @State private var showBrewHasNoUpdate = false

  var body: some View {
    HStack {
      if updateAppList.isEmpty {
        checkUpdateButton
      } else {
        VStack(alignment: .leading) {
          upgradeButton

          List(updateAppList, id: \.self) { app in
            Text(app)
          }
          .cornerRadius(12)
        }
      }

      if terminalRunning {
        ProgressView()
          .controlSize(.small)
      }
    }
    .alert("Brew has no updates.", isPresented: $showBrewHasNoUpdate) {

    }
  }

  /*
   每隔2小时更新brew到最新
   检测brew是否有更新包
   如果有，则通知用户有更新
   */

  /// 更新Homebrew自身
  /// - Returns: 更新结果输出
  func updateBrew() {
    shell("/opt/homebrew/bin/brew update")
  }

  /// 检查Homebrew包是否有可用更新
  /// - Returns: 需要更新的包列表
  func checkBrewUpdate() -> [String] {
    // 先更新brew自身
    updateBrew()

    // 然后检查过时的包
    let output = shell("/opt/homebrew/bin/brew outdated")
    let outdatedPackages = output.split(separator: "\n").map(String.init)
    return outdatedPackages
  }

  func upgradeBrew() -> String {
    return shell("/opt/homebrew/bin/brew upgrade")
  }
}

extension BrewView {
  var checkUpdateButton: some View {
    Button("Check Update") {
      Task {
        terminalRunning = true

        try await Task.sleep(nanoseconds: 1000) // 动画需要

        defer {
          terminalRunning = false
        }

        let updateAppList = checkBrewUpdate()

        if updateAppList.isEmpty {
          // 通知已经是最新
          showBrewHasNoUpdate = true
        } else {
          self.updateAppList = checkBrewUpdate()
        }
      }
    }
  }

  var upgradeButton: some View {
    Button("Upgrade") {
      Task {
        terminalRunning = true

        try await Task.sleep(nanoseconds: 1000)

        defer {
          terminalRunning = false
          updateAppList.removeAll()
        }

        self.brewUpgradeResult = upgradeBrew()
        self.showBrewUpgadeAlert = true
      }
    }
    .alert("Brew Upgrade", isPresented: $showBrewUpgadeAlert) {
    } message: {
      if let brewUpgradeResult {
        Text(brewUpgradeResult)
      }
    }
  }
}

#Preview {
  BrewView()
}
