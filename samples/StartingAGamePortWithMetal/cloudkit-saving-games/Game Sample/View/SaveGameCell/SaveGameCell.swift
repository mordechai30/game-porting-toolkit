/*
<samplecode>
  <abstract>
  Cell view to show a saved game in main view.
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

struct SaveGameCell: View {
    let saveGameRecord: SaveGameRecord
    
    private var saveGame: SaveGame { saveGameRecord.game }
    
    var body: some View {
        HStack {
            Image(systemName: "star.square.fill")
                .font(.largeTitle)
                .foregroundStyle(chapter.color)
            
            LabeledContent {
                GameView.createBasicCheckpointIndicatorView(chapter, status: saveGame.status)
                    .foregroundStyle(chapter.color)
            } label: {
                Text("Save \(saveGameRecord.localIdentifier)")
                Text(chapter.title)
                    .bold()
                    .foregroundStyle(chapter.color)
                Text(formatTimePlayed(saveGame.timePlayed) + " • " + formatLastPlayed(saveGame.lastPlayed))
            }
        }
    }
    
    private var chapter: GameChapter {
        return saveGame.chapter
    }
    
    // MARK: - Formatters
    
    func formatTimePlayed(_ duration: Duration) -> String {
        return duration.formatted()
    }
    
    func formatLastPlayed(_ date: Date?) -> String {
        guard let date = date else { return "Start your game" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .spellOut
        
        return formatter.localizedString(for: date, relativeTo: .now.advanced(by: 1))
    }
}

#Preview {
    @Previewable @State var startedGameRecord = SaveGameRecord(localIdentifier: 1,
                                                  game: {
        let game = SaveGame()
        game.proceedGame(.night, timePlayed: .seconds(12))
        return game
    }())
    
    return SaveGameCell(saveGameRecord: startedGameRecord)
}
