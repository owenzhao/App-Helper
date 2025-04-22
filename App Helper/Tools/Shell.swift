//
//  Shell.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation

@discardableResult
func shell(_ command: String, timeout: TimeInterval = 600) -> String {
  let task = Process()
  let pipe = Pipe()
  task.standardOutput = pipe
  task.standardError = pipe
  task.arguments = ["-c", command]
  task.launchPath = "/bin/zsh"
  task.standardInput = nil

  // 在主队列之外异步启动
  task.launch()

  // 使用 DispatchGroup + DispatchSemaphore 实现超时控制
  let group = DispatchGroup()
  var output: String = ""

  group.enter()

  DispatchQueue.global().async {
    if let data = try? pipe.fileHandleForReading.readToEnd() {
      output = String(data: data, encoding: .utf8) ?? ""
    }
    group.leave()
  }

  // 等待 group，带超时
  let waitResult = group.wait(timeout: .now() + timeout)
  if waitResult == .timedOut {
    // 超时之后杀死 task
    if task.isRunning {
      task.terminate()
    }
    return "执行超时"
  }

  return output
}
