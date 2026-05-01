//
//  ContentView.swift
//  markthisdown
//
//  Created by Levi on 5/1/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: markthisdownDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(markthisdownDocument()))
}
