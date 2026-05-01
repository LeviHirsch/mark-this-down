//
//  markthisdownApp.swift
//  markthisdown
//
//  Created by Levi on 5/1/26.
//

import SwiftUI

@main
struct markthisdownApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: markthisdownDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
