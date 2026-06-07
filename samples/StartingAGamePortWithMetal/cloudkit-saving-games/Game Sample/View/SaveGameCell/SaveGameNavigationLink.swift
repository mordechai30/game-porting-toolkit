/*
<samplecode>
  <abstract>
  Custom navigation link view for the main content view to show and open a saved game.
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

struct SaveGameNavigationLink: View {

    @Environment(GameSaveModel.self) var gsm: GameSaveModel

    let saveGameRecord: SaveGameRecord
    
    private var saveGame: SaveGame { saveGameRecord.game }
    
    var body: some View {
        NavigationLink(value: saveGame) {
            if saveGame.chapter == .night && saveGame.status == .notStarted {
                bodyForFreshGame
            } else {
                bodyForStartedGame
            }
        }
        .frame(minHeight: 50)
        
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    try await gsm.deleteGame(saveGameRecord.localIdentifier)
                }
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        }
    }
    
    var bodyForStartedGame: some View {
        SaveGameCell(saveGameRecord: saveGameRecord)
    }
    
    var bodyForFreshGame: some View {
        HStack {
            Image(systemName: "play.square.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            LabeledContent {
            } label: {
                Text(formatLastPlayed(saveGame.lastPlayed))
            }
        }
    }
    
    func formatLastPlayed(_ date: Date?) -> String {
        guard let date = date else { return "Start your game" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .spellOut
        
        return formatter.localizedString(for: date, relativeTo: .now.advanced(by: 1))
    }
    
    // MARK: - Helpers
    
    var chapter: GameChapter {
        return saveGame.chapter
    }
}

#Preview {
    @Previewable @State var freshGameRecord = SaveGameRecord(localIdentifier: 1,
                                                game: .init())
    @Previewable @State var startedGameRecord = SaveGameRecord(localIdentifier: 2,
                                                  game: {
        let game = SaveGame()
        game.proceedGame(.day, timePlayed: .seconds(12))
        return game
    }()
    )
    
    return NavigationStack {
        List {
            SaveGameNavigationLink(saveGameRecord: freshGameRecord)
                .environment(GameSaveModel.shared)
            SaveGameNavigationLink(saveGameRecord: startedGameRecord)
                .environment(GameSaveModel.shared)
        }
    }
}
