//
//  ContentView.swift
//  VeilWalker
//
//  Created by Premise LLC on 10/30/26.
//

import SwiftUI

/// Root: the one-screen home, with every other screen pushed on top.
struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [Screen] = []

    var body: some View {
        if !app.consented {
            ConsentView().preferredColorScheme(.dark)
        } else {
            home
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .journeys: JourneysView(path: $path)
                    case .journey(let id): JourneyDetailView(id: id)
                    case .peak(let id): PeakDetailView(id: id)
                    case .stats: StatsView()
                    case .badges: BadgesView()
                    case .about: AboutView()
                    case .account: AccountView()
                    case .social: SocialView()
                    case .brag: BragView()
                    case .credits: CreditsView()
                    case .snowflake: SnowflakeView()
                    }
                }
        }
        .tint(Veil.violet)
        .preferredColorScheme(.dark)
        .onChange(of: app.consented) { path = [] }   // account deleted: start over from the home screen
    }
}
