//
//  LogView.swift
//  App Helper
//
//  Created by zhaoxin on 2023/3/19.
//

import CoreData
import SwiftUI

struct LogView: View {
  @Environment(\.managedObjectContext) private var managedObjectContext
  @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdDate", ascending: false)]) private var logs: FetchedResults<AHLog>

  var body: some View {
    if logs.isEmpty {
      Text("No Logs")
        .font(.title)
        .padding()
    } else {
      List(logs) { log in
        HStack {
          Text(DateFormatter.localizedString(from: log.createdDate!, dateStyle: .medium, timeStyle: .medium))
          Spacer()
          Text(log.text!)
        }
      }
    }
  }
}

struct LogView_Previews: PreviewProvider {
  static var previews: some View {
    LogView()
  }
}
