//
//  VeilWalkerApp.swift
//  VeilWalker
//
//  Created by Premise LLC on 10/30/26.
//

import SwiftUI

@main
struct VeilWalkerApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .task {
                    app.launch()
                    await app.foreground()
                }
        }
        // Hourly-ish background sync (Android: WorkManager). iOS decides when; the app asks for every hour or so.
        .backgroundTask(.appRefresh(AppModel.syncTaskId)) {
            await app.backgroundSync()
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active: Task { await app.foreground() }
            case .background: app.background()
            default: break
            }
        }
    }
}
