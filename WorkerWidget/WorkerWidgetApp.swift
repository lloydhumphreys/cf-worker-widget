//
//  WorkerWidgetApp.swift
//  WorkerWidget
//
//  Created by Lloyd Humphreys on 14/06/2025.
//

import SwiftUI

@main
struct WorkerWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        Settings {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
