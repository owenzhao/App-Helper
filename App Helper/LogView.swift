//
//  LogView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/19.
//

import AppKit
import CoreData
import SwiftUI

struct LogView: View {
  @Environment(\.managedObjectContext) private var managedObjectContext
  @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdDate", ascending: false)]) private var logs: FetchedResults<AHLog>

  @State private var searchText = ""
  @State private var showClearConfirmation = false

  var body: some View {
    Group {
      if logs.isEmpty {
        AHLogEmptyState(
          systemImage: "tray",
          title: NSLocalizedString("No Logs", comment: "Empty state title when there are no log entries"),
          message: NSLocalizedString("Matched rules and cleanup events will show up here.", comment: "Empty state message for the log list")
        )
      } else if dayGroups.isEmpty {
        AHLogEmptyState(
          systemImage: "magnifyingglass",
          title: NSLocalizedString("No matching logs.", comment: "Empty state title when a search matches nothing"),
          message: NSLocalizedString("Try a different search term.", comment: "Empty state message when a search matches nothing")
        )
      } else {
        logList
      }
    }
    .frame(minWidth: 560, minHeight: 520)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        AHLogSearchField(
          text: $searchText,
          placeholder: NSLocalizedString("Search logs", comment: "Log search field placeholder")
        )
        .frame(width: 200)
      }

      ToolbarItem(placement: .automatic) {
        Button {
          showClearConfirmation = true
        } label: {
          Label {
            Text("Clear Logs", comment: "Button that deletes every log entry")
          } icon: {
            Image(systemName: "trash")
          }
        }
        .disabled(logs.isEmpty)
        .help(NSLocalizedString("Clear Logs", comment: "Button that deletes every log entry"))
      }
    }
    .confirmationDialog(
      Text("Clear All Logs?", comment: "Clear logs confirmation title"),
      isPresented: $showClearConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear", role: .destructive) {
        clearLogs()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This deletes every log entry and cannot be undone.", comment: "Clear logs confirmation message")
    }
  }
}

// MARK: - Log list
private extension LogView {
  var logList: some View {
    List {
      ForEach(dayGroups) { group in
        Section {
          ForEach(group.entries, id: \.objectID) { log in
            AHLogRow(log: log)
          }
        } header: {
          AHLogDayHeader(date: group.date, count: group.entries.count)
        }
      }
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
  }

  var filteredLogs: [AHLog] {
    let all = Array(logs)
    guard searchText.isEmpty == false else {
      return all
    }

    return all.filter { ($0.text ?? "").localizedCaseInsensitiveContains(searchText) }
  }

  var dayGroups: [AHLogDayGroup] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: filteredLogs) { log in
      calendar.startOfDay(for: log.createdDate ?? Date.distantPast)
    }

    return grouped
      .map { AHLogDayGroup(date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
  }

  func clearLogs() {
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "AHLog")
    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    deleteRequest.resultType = .resultTypeObjectIDs

    do {
      let result = try managedObjectContext.execute(deleteRequest) as? NSBatchDeleteResult
      if let objectIDs = result?.result as? [NSManagedObjectID] {
        NSManagedObjectContext.mergeChanges(
          fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
          into: [managedObjectContext]
        )
      }
    } catch {
      print(error)
    }
  }
}

// MARK: - Row components
private struct AHLogDayGroup: Identifiable {
  let date: Date
  let entries: [AHLog]

  var id: Date { date }
}

private struct AHLogDayHeader: View {
  let date: Date
  let count: Int

  var body: some View {
    HStack(spacing: 6) {
      Text(Self.title(for: date))
        .font(.subheadline.weight(.semibold))

      Text(verbatim: "\(count)")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))

      Spacer()
    }
    .padding(.top, 4)
  }

  private static func title(for date: Date) -> String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
      return NSLocalizedString("Today", comment: "Log section header for today")
    }

    if calendar.isDateInYesterday(date) {
      return NSLocalizedString("Yesterday", comment: "Log section header for yesterday")
    }

    if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
      return date.formatted(.dateTime.month(.wide).day())
    }

    return date.formatted(.dateTime.year().month(.wide).day())
  }
}

private struct AHLogRow: View {
  let log: AHLog

  private var kind: AHLogKind {
    AHLogKind(text: log.text ?? "")
  }

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: kind.systemImage)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(kind.tint)
        .frame(width: 20, height: 20)
        .background(Circle().fill(kind.tint.opacity(0.15)))

      Text(log.text ?? "")
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      Spacer(minLength: 12)

      Text(log.createdDate?.formatted(date: .omitted, time: .shortened) ?? "")
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

private struct AHLogEmptyState: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(.tertiary)

      Text(title)
        .font(.headline)

      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Search field
private struct AHLogSearchField: NSViewRepresentable {
  @Binding var text: String
  let placeholder: String

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = placeholder
    field.delegate = context.coordinator
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    return field
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    private let text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSSearchField else {
        return
      }

      text.wrappedValue = field.stringValue
    }
  }
}

// MARK: - Log categorisation
private enum AHLogKind {
  case start
  case restart
  case quit
  case cleanup
  case failure
  case warning
  case info

  /// Localized log lines are free text, so the kind is inferred from the same
  /// action words and format strings `SystemWatcher` writes.
  private static let suffixes: [(AHAction, AHLogKind)] = [
    (.restart, .restart),
    (.start, .start),
    (.quit, .quit),
    (.failed, .failure),
  ]

  private static let prefixes: [(String, AHLogKind)] = [
    (NSLocalizedString("Can not clean up %@.", comment: ""), .failure),
    (NSLocalizedString("Can not quit %@.", comment: ""), .failure),
    (NSLocalizedString("Clean up %@ remains.", comment: ""), .cleanup),
    (NSLocalizedString("Quit %@", comment: ""), .quit),
    (NSLocalizedString("Xcode uses high CPU!", comment: ""), .warning),
  ]

  init(text: String) {
    for (action, kind) in Self.suffixes where text.hasSuffix(action.localizedString) {
      self = kind
      return
    }

    for (format, kind) in Self.prefixes {
      let literal = format.components(separatedBy: "%@").first ?? format
      if literal.isEmpty == false, text.hasPrefix(literal) {
        self = kind
        return
      }
    }

    self = .info
  }

  var systemImage: String {
    switch self {
    case .start:
      return "play.fill"
    case .restart:
      return "arrow.clockwise"
    case .quit:
      return "stop.fill"
    case .cleanup:
      return "trash"
    case .failure:
      return "exclamationmark.triangle.fill"
    case .warning:
      return "bolt.fill"
    case .info:
      return "info.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .start:
      return .green
    case .restart:
      return .blue
    case .quit:
      return .secondary
    case .cleanup:
      return .teal
    case .failure:
      return .red
    case .warning:
      return .orange
    case .info:
      return .secondary
    }
  }
}

struct LogView_Previews: PreviewProvider {
  static var previews: some View {
    LogView()
  }
}
