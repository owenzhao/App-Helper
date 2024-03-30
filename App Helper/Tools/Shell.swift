//
//  Shell.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import Foundation

func shell(_ command: String) -> String {
  let task = Process()
  let pipe = Pipe()

  task.standardOutput = pipe
  task.standardError = pipe
  task.arguments = ["-c", command]
  task.launchPath = "/bin/zsh"
  task.standardInput = nil
  task.launch()

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let output = String(data: data, encoding: .utf8)!

  return output
}
