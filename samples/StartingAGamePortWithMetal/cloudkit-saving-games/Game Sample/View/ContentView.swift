/*
<samplecode>
  <abstract>
  The app's main view on launch.
  </abstract>
</samplecode>
*/

//-------------------------------------------------------------------------------------------------------------------------------------------------------------
//
// Copyright 2026 Apple Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-------------------------------------------------------------------------------------------------------------------------------------------------------------

import SwiftUI
import os.log

struct ContentView: View {
    @Environment(GameSaveModel.self) var gsm: GameSaveModel
    
    @State private var selectedGame: SaveGame?
    
    @State private var isSheetPresented = false
    
    @State private var gamePresentedInSheet: SaveGame?
    @State private var selectedVersion: SaveVersion?
    @State private var selectedGameID: SaveGameRecord.LocalIdentifier?
    
    @State private var activeGame: SaveGame?
    
    // MARK: - View elements
    
    var body: some View {
        NavigationStack {
            List {
                createPlayGameSection
            }
            .navigationDestination(for: SaveGame.self, destination: { game in
                GameView(game: game)
                    .environment(gsm)
            })
            
            .task {
                await initializeGameSaveModelOnAppear()
                gsm.loadLocalGame()
            }
            
            .sheet(isPresented: $isSheetPresented, onDismiss: {
                guard let selectedVersion = selectedVersion else {
                    print("No selected version from resolve.")
                    return
                }
                Task {
                    await gsm.resolveWithVersion(selectedVersion)
                    gsm.loadLocalGame()
                }
            }, content: {
                SyncSheet(selectedVersion: $selectedVersion)
                    .padding(.vertical, 50)
                #if os(macOS)
                    .frame(minWidth: 500)
                #else
                    .frame(minWidth: 300)
                #endif
            })
            
            .navigationTitle("Sample Game")
            
            .animation(.default, value: gsm.saveGameRecords)
        }
    }
    
    var createPlayGameSection: some View {
        Section {
            ForEach(sortedGameSaves) { record in
                SaveGameNavigationLink(saveGameRecord: record)
                    .environment(gsm)
            }
            .onDelete(perform: { indexSet in
                Task {
                    await deleteSaveGame(at: indexSet)
                }
            })
        } header: {
            if !gsm.saveGameRecords.isEmpty {
                createPlayNowSectionHeaderText
            }
        } footer: {
            if gsm.saveGameRecords.count == Config.maxSaveGameCount {
                createPlayNowSectionFooterText
            }
        }
    }
    
    var createPlayNowSectionHeaderText: some View {
        Text("Play Now")
    }
    
    var createPlayNowSectionFooterText: some View {
        Text("Save up to \(Config.maxSaveGameCount) games. Swipe left or use the context menu to delete.")
    }
    
    // MARK: - View data formatting
    
    var sortedGameSaves: [SaveGameRecord] {
        return gsm.saveGameRecords
    }
    
    // MARK: - Actions
    
    func initializeGameSaveModelOnAppear() async {
        isSheetPresented = true
        await gsm.sync()
        if gsm.syncState == nil {
            isSheetPresented = false
        }
    }
    
    func deleteSaveGame(at indexSet: IndexSet) async {
        guard let firstIndex = indexSet.first else {
            return
        }
        
        let saveGame = sortedGameSaves[firstIndex]
        
        do {
            try await gsm.deleteGame(saveGame.localIdentifier)
        } catch {
            print("Could not delete game: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView().environment(GameSaveModel.shared)
}
