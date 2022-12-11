//
//  AppDetailView.swift
//  App Helper
//
//  Created by zhaoxin on 2022/12/11.
//

import SwiftUI

struct AppDetailView: View {
    @Binding var app:AHApp
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(nsImage: getImage())
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(app.name ?? "No Name")
                    .font(.title)
                .foregroundColor(.blue)
            }
        }
        .padding()
    }
    
    private func getImage() -> NSImage {
        let workspace = NSWorkspace.shared
        return workspace.icon(forFile: app.url.path)
    }
}

struct AppDetailView_Previews: PreviewProvider {
    static var previews: some View {
        AppDetailView(app: .constant(AHApp(name: "MonitorControl",
                                           url: URL(fileURLWithPath: "/Applications/MonitorControl.app"),
                                           bundleID: "me.guillaumeb.MonitorControl")))
    }
}
