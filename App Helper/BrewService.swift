import Foundation

// 创建一个单例来管理 Brew 操作
class BrewService {
  static let shared = BrewService()

  private init() {}

  func updateBrew() {
    shell("/opt/homebrew/bin/brew update")
  }

  func checkBrewUpdate() -> [String] {
    updateBrew()
    return getBrewOutdated()
  }

  func getBrewOutdated() -> [String] {
    let output = shell("/opt/homebrew/bin/brew outdated")
    return output.split(separator: "\n").map(String.init)
  }

  func upgradeBrew() -> String {
    return shell("/opt/homebrew/bin/brew upgrade")
  }
}

