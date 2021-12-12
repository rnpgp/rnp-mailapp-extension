//
//  ContentView.swift
//  MailExtensionsContainer
//
//  Created by Sergey Vinogradov on 30.11.2021.
//

import SwiftUI

struct KeyFile: Identifiable {
    let id = UUID()
    let filename: String
    let isPublic: Bool
}

extension KeyFile {
    static var mock: [KeyFile] {
        [
            KeyFile(filename: "pubring.gpg", isPublic: true),
            KeyFile(filename: "secring.gpg", isPublic: false)
        ]
    }
}

struct ContentView: View {
    private let keyFiles = KeyFile.mock
    
    var body: some View {
        VStack {
            Text("Keys manager")
            
            HStack {
                Group {
                    Button {} label: {
                        Image(systemName: "plus.circle")
                    }
                    
                    Button {} label: {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(true)
                    
                    Button {} label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(true)
                }
                .font(.system(size: 40))
                .buttonStyle(.borderless)
            }
            .padding()
            
            Table {
                TableColumn("Filename", value: \.filename)
            } rows: {
                ForEach(keyFiles) { value in
                    TableRow(value)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
