//
//  CodeCleanerView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/10/4.
//

import SwiftUI
import Defaults

struct CodeCleanerView: View {
  @State private var codeText: String = ""
  @Default(.tabSpace) private var tabSpace

  var body: some View {
    TextEditor(text: $codeText)
      .textEditorStyle(.plain)
      .padding(Style.dropAreaCornerRadius)
      .background(Style.dropAreaBackground)
      .cornerRadius(Style.dropAreaCornerRadius)
      .onChange(of: codeText) {
        run()
      }
  }


  /// 整理代码
  private func run() {
    if codeText.isEmpty { return }

    var lines = codeText.components(separatedBy: .newlines)
    lines = removeLeadingAndTrailingEmptyLines(from: lines)

    if lines.count == 1 {
      codeText = lines[0].trimmingCharacters(in: .whitespaces)
      return
    }

    if lines.count == 2 {
      let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
      let secondLine = lines[1].trimmingCharacters(in: .whitespaces)
      codeText = firstLine + "\n" + secondLine
      return
    }

    // 3+ lines: 1. 首行和尾行移除首尾空格，2. 其他行保留合理缩进，3. 统一缩进为tabSpace个空格
    let firstLine = lines.first!.trimmingCharacters(in: .whitespaces)
    let lastLine = lines.last!.trimmingCharacters(in: .whitespaces)
    let middleLines = Array(lines.dropFirst().dropLast())
    let normalizedMiddle = middleLines.map { normalizeIndentation($0, tabSpace: tabSpace) }
    // 尾行移除所有首部缩进
    let cleanedLastLine = lastLine.replacingOccurrences(of: "^ +", with: "", options: .regularExpression)
    let resultLines = [firstLine] + normalizedMiddle + [cleanedLastLine]
    // 移除多余的连续空行（只保留一个）
    codeText = removeConsecutiveEmptyLines(from: resultLines).joined(separator: "\n")
  }

  /// 统一行首缩进为tabSpace个空格
  private func normalizeIndentation(_ line: String, tabSpace: Int) -> String {
    let trimmed = line.replacingOccurrences(of: "^([ \t]+)", with: "", options: .regularExpression)
    let indentLevel = countIndentLevel(line)
    let indent = String(repeating: " ", count: indentLevel * tabSpace)
    return indent + trimmed
  }

  /// 计算缩进级别（假设每tabSpace个空格或一个tab为一级）
  private func countIndentLevel(_ line: String) -> Int {
    var count = 0
    var i = line.startIndex
    while i < line.endIndex {
      if line[i] == "\t" {
        count += 1
        i = line.index(after: i)
      } else if line[i] == " " {
        var spaceCount = 0
        while i < line.endIndex && line[i] == " " && spaceCount < tabSpace {
          spaceCount += 1
          i = line.index(after: i)
        }
        if spaceCount == tabSpace {
          count += 1
        }
      } else {
        break
      }
    }
    return count
  }

  /// 移除顶部和底部的空行
  private func removeLeadingAndTrailingEmptyLines(from lines: [String]) -> [String] {
    var result = lines
    while let first = result.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
      result.removeFirst()
    }
    while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      result.removeLast()
    }
    return result
  }

  /// 移除多余的连续空行，只保留一个空行
  private func removeConsecutiveEmptyLines(from lines: [String]) -> [String] {
    var result: [String] = []
    var emptyLineCount = 0
    for line in lines {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        emptyLineCount += 1
        if emptyLineCount <= 1 {
          result.append("")
        }
      } else {
        emptyLineCount = 0
        result.append(line)
      }
    }
    return result
  }
}

#Preview {
  CodeCleanerView()
}
