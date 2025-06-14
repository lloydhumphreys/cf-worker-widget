//
//  WorkerBuildHistoryApp.swift
//  WorkerBuildHistory
//
//  Created by Lloyd Humphreys on 14/06/2025.
//

import SwiftUI

@main
struct WorkerBuildHistoryApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
