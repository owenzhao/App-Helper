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
  static let closeButtonSize: CGFloat = 14 // NSWindow close button size
  static let closeButtonColor = Color(red: 1.0, green: 0.23, blue: 0.19)
  static let closeButtonXColor = Color.black // macOS standard is black
  static let closeButtonTopBarHeight: CGFloat = 24 // Documented for spacing
  static let displaySectionTopMargin: CGFloat = 6 // Margin between close button and display section
}

struct WindowCloseButton: View {
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(AppMenuStyle.closeButtonColor)
          .frame(width: AppMenuStyle.closeButtonSize, height: AppMenuStyle.closeButtonSize)
        if isHovering {
          Text("×", comment: "NSWindow style close button x")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(AppMenuStyle.closeButtonXColor)
        }
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovering = hovering
    }
    .accessibilityLabel(Text("Close", comment: "Accessibility label for NSWindow style close button"))
  }
}

struct AppMenuPopoverView: View {
  let openMainApp: () -> Void
  let closePopover: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Content (right aligned, no top margin)
      VStack(alignment: .trailing, spacing: 12) {
        // Display quick actions from the main app
        RulesView.DisplaySectionView()
      }
      .padding(.horizontal, AppMenuStyle.contentPadding)
      .padding(.bottom, AppMenuStyle.contentPadding)
      // Footer with primary action (right aligned)
      footerBar
    }
    .controlSize(.small)
    .overlay(
      WindowCloseButton(action: closePopover)
        .padding(.top, 8)
        .padding(.leading, 8),
      alignment: .topLeading
    )
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
    AppMenuPopoverView(openMainApp: {}, closePopover: {})
      .frame(width: 360)
  }
}
