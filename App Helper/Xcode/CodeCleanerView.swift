//
//  CodeCleanerView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/10/4.
//

import SwiftUI
import Defaults

struct TabSpaceSettingView: View {
  @Default(.tabSpace) private var tabSpace

  var body: some View {
    HStack {
      Text("Tab width", comment: "Label for tab width setting in code cleaner")
      Stepper(value: $tabSpace, in: 1...8) {
        Text("\(tabSpace) spaces", comment: "Stepper value for tab width in code cleaner")
      }
    }
    .padding(.bottom, 8)
  }
}

struct CodeCleanerView: View {
  @State private var codeText: String = ""
  @Default(.tabSpace) private var tabSpace
  @State private var showCopiedPopover = false

  var body: some View {
    VStack {
      HStack(alignment: .center) {
        Text("Code Cleaner", comment: "Code Cleaner section title")
          .font(.title.bold())
        Spacer()
        TabSpaceSettingView()
      }
      
      TextEditor(text: $codeText)
        .textEditorStyle(.plain)
        .font(.system(size: 14, design: .monospaced)) // Use monospaced font for code editing
        .padding(Style.dropAreaCornerRadius)
        .background(Style.dropAreaBackground)
        .cornerRadius(Style.dropAreaCornerRadius)
        .frame(minHeight: 300)
        .onChange(of: codeText) {
          run()
        }
        .onChange(of: tabSpace) {
          run()
        }
      Button(action: copyToClipboard, label: {
        Text("Copy", comment: "Button to copy code text")
          .frame(maxWidth: .infinity)
          .padding()
      })
      .popover(isPresented: $showCopiedPopover) {
        Text("Copied", comment: "Popover message after copying code")
          .font(.system(size: 14, design: .monospaced))
          .padding()
      }
    }
    .padding()
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

    let firstLine = lines.first!.trimmingCharacters(in: .whitespaces)
    let lastLine = lines.last!.trimmingCharacters(in: .whitespaces)
    let middleLines = Array(lines.dropFirst().dropLast())
    let normalizedMiddle = middleLines.map { normalizeIndentation($0, tabSpace: tabSpace) }
    let cleanedLastLine = lastLine.replacingOccurrences(of: "^ +", with: "", options: .regularExpression)
    let resultLines = [firstLine] + normalizedMiddle + [cleanedLastLine]
    codeText = removeConsecutiveEmptyLines(from: resultLines).joined(separator: "\n")
  }

  /// 统一行首缩进为tabSpace个空格
  private func normalizeIndentation(_ line: String, tabSpace: Int) -> String {
    let trimmed = line.replacingOccurrences(of: "^([ \t]+)", with: "", options: .regularExpression)
    let indentLevel = countIndentLevel(line, tabSpace: tabSpace)
    let indent = String(repeating: " ", count: indentLevel * tabSpace)
    return indent + trimmed
  }

  /// 计算缩进级别（假设每tabSpace个空格或一个tab为一级）
  private func countIndentLevel(_ line: String, tabSpace: Int) -> Int {
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

  private func copyToClipboard() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(codeText, forType: .string)
    showCopiedPopover = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      showCopiedPopover = false
    }
  }
}

#Preview {
  CodeCleanerView()
}
