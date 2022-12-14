//
//  ContentView.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import SwiftUI
import Defaults
import SwiftUIWindowBinder

struct ContentView: View {
    @Default(.apps) private var apps
    @State private var selection = Set<AHApp>()
    @State private var window: SwiftUIWindowBinder.Window?
    
    var body: some View {
        WindowBinder(window: $window) {
            VStack(alignment: .leading) {
                if apps.isEmpty {
                    Text("No Apps were controlled.")
                        .font(.title2)
                        .foregroundColor(.blue)
                } else {
                    List($apps, id:\.self, selection: $selection) { $app in
                        AppDetailView(app: $app)
                    }
                    .onDeleteCommand {
                        if let app = selection.first, let index = apps.firstIndex(of: app) {
                            apps.remove(at: index)
                        }
                    }
                }
                
                HStack {
                    Button("Add App") {
                        let panel = NSOpenPanel()
                        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask).first
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.init(filenameExtension: "app", conformingTo: .package)!]
                        
                        let response = panel.runModal()
                        
                        if response == .OK, let url = panel.url {
                            let name = url.deletingPathExtension().lastPathComponent
                            let bundleID = shell("mdls -name kMDItemCFBundleIdentifier -r '\(url.path)'")
                            let app = AHApp(name: name, url: url, bundleID: bundleID)
                            apps.append(app)
                        }
                    }
                    
                    Button("Run in Background") {
                        NotificationCenter.default.post(name: .simulatedWindowClose, object: self)
                    }
                    
                    Text("To remove a controlled app, select and press \"delete\" button on the keyboard.")
                        .font(.footnote)
                        .foregroundColor(.green)
                }
            }
            .padding()
        }
        .onChange(of: window) { newValue in
            if let window = newValue {
                window.delegate = WindowDelegate.shared
                NotificationCenter.default.post(name: .updateWindow, object: nil, userInfo: ["window" : window])
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct AHApp:Codable, Defaults.Serializable, Identifiable, Equatable, Hashable {
    var id:String  { return bundleID }
    let name:String?
    let url:URL
    let bundleID:String
}
