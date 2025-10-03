//
//  XcodeView.swift
//  App Helper
//
//  Created by zhaoxin on 2025/8/4.
//

import SwiftUI

// Documented: Style struct for interface consistency
struct Style {
  static let dropAreaBackground = Color.gray.opacity(0.1) // drop area background color
  static let dropAreaCornerRadius: CGFloat = 12           // drop area corner radius
  static let dropAreaPadding: CGFloat = 24                // drop area padding
  static let dropAreaShadowRadius: CGFloat = 4            // drop area shadow radius
  static let buttonBackground = Color.accentColor.opacity(0.15) // button background color
  static let buttonCornerRadius: CGFloat = 8                    // button corner radius
  static let buttonPadding: CGFloat = 12                        // button padding

  // Add to Style struct
  static let terminalBackground = Color.black.opacity(0.85) // terminal output background
  static let terminalCornerRadius: CGFloat = 6              // terminal output corner radius
}

struct FileDropAreaView: View {
  @Binding var fileURL: URL?
  
  var body: some View {
    VStack {
      Text("Drag your project file here", comment: "Prompt for project drag-and-drop")
        .foregroundColor(.secondary)
      if let url = fileURL {
        Text(url.absoluteString)
          .font(.footnote)
          .foregroundColor(.primary)
          .padding(.top, 8)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 120)
    .padding(Style.dropAreaPadding)
    .background(Style.dropAreaBackground)
    .cornerRadius(Style.dropAreaCornerRadius)
    .shadow(radius: Style.dropAreaShadowRadius)
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      if let provider = providers.first {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          DispatchQueue.main.async {
            self.fileURL = url
          }
        }
        return true
      }
      return false
    }
  }
}

struct SPMDependencyButtonView: View {
  let fileURL: URL?
  @Binding var result: String?
  @State private var isLoading = false
  
  var body: some View {
    VStack {
      Button(action: getSPMDependencies) {
        Text("Get SPM Dependencies", comment: "Button to resolve SPM dependencies")
          .padding(Style.buttonPadding)
          .frame(maxWidth: .infinity)
      }
      .disabled(fileURL == nil || isLoading)
      if isLoading {
        ProgressView()
          .padding(.top, 8)
      }
      // In SPMDependencyButtonView
      if let result {
        Text(result)
          .font(.system(.body, design: .monospaced))
          .foregroundColor(.green)
          .padding(12)
          .background(Style.terminalBackground)
          .cornerRadius(Style.terminalCornerRadius)
          .padding(.top, 8)
          .lineLimit(10)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func getSPMDependencies() {
    guard let url = fileURL else { return }
    isLoading = true
    DispatchQueue.global().async {
      let command = buildSPMCommand(for: url)
      let output = shell(command)
      DispatchQueue.main.async {
        self.result = output
        self.isLoading = false
      }
    }
  }
  
  private func isSPMPackageDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    let fileManager = FileManager.default
    let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
    if exists && isDir.boolValue {
      let packageFile = url.appendingPathComponent("Package.swift")
      return fileManager.fileExists(atPath: packageFile.path)
    }
    return false
  }
  
  private func buildSPMCommand(for url: URL) -> String {
    let path = url.path
    if path.hasSuffix(".xcodeproj") {
      return "xcodebuild -resolvePackageDependencies -project \"\(path)\""
    } else if path.hasSuffix(".xcworkspace") {
      return "xcodebuild -resolvePackageDependencies -workspace \"\(path)\""
    } else if isSPMPackageDirectory(url) {
      return "cd \"\(path)\" && swift package resolve"
    } else {
      return "echo 'Unsupported file type'"
    }
  }
}

// Extension for XcodeView to keep main body concise
extension XcodeView {
  var fileDropArea: some View {
    FileDropAreaView(fileURL: $fileURL)
  }
  var spmDependencyButton: some View {
    SPMDependencyButtonView(fileURL: fileURL, result: $spmResult)
  }
}

// Usage in XcodeView
struct XcodeView: View {
  @State private var fileURL: URL?
  @State private var spmResult: String?
  
  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        Text("Xcode integration features", comment: "Xcode tab description")
          .font(.title.bold())
        fileDropArea
        spmDependencyButton
        Spacer()
      }
      .padding()
    }
  }
}

#Preview {
  XcodeView()
}
