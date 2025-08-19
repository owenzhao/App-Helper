//  AppMenuPopoverView.swift
//  App Helper
//
//  Created by GitHub Copilot on 2025/08/20.
//
//  A compact SwiftUI view used inside the menubar popover. It embeds the
//  DisplaySectionView for quick access, and provides a button to open the main app.

import SwiftUI

private enum AppMenuStyle {
  static let contentPadding: CGFloat = 12
  static let footerCornerRadius: CGFloat = 10
  static let footerPadding: EdgeInsets = .init(top: 8, leading: 12, bottom: 0, trailing: 12)
}

struct AppMenuPopoverView: View {
  let openMainApp: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Content
      VStack(alignment: .leading, spacing: 12) {
        // Display quick actions from the main app
        RulesView.DisplaySectionView()
      }
      .padding(AppMenuStyle.contentPadding)

      // Footer with primary action
      footerBar
    }
    .controlSize(.small)
  }

  private var footerBar: some View {
    HStack {
      Spacer()
      Button(action: openMainApp) {
        Text("Open Main App", comment: "Button to open the main application window from popover")
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(AppMenuStyle.footerPadding)
    .background(
      RoundedRectangle(cornerRadius: AppMenuStyle.footerCornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
    )
    .padding(.horizontal, 6)
    .padding(.bottom, 6)
  }
}

struct AppMenuPopoverView_Previews: PreviewProvider {
  static var previews: some View {
    AppMenuPopoverView(openMainApp: {})
      .frame(width: 360)
  }
}
