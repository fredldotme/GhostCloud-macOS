//
//  GhostCloud_macOSApp.swift
//  GhostCloud-macOS
//
//  Created by Alfred Neumayer on 17.06.21.
//

import SwiftUI

@main
struct GhostCloudApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 450, idealWidth: 450, maxWidth: .infinity, minHeight: 400, idealHeight: 400, maxHeight: .infinity, alignment: .center)
        }.commands {
            CommandGroup(replacing: .newItem, addition: { })
        }
    }
}
