/*
<samplecode>
  <abstract>
  The gameplay view.
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

struct GameView: View {
    
    @Environment(GameSaveModel.self) var gsm: GameSaveModel
    @Bindable var game: SaveGame
    
    @State private var timePlayedSinceLastSave = Duration.seconds(0)
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // MARK: - View elements
    
    var body: some View {
        List {
            ForEach(GameChapter.allCases) { chapter in
                createChapterEntrypointView(chapter)
                    .listRowSeparator(.hidden)
            }
            createFootnotesView()
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .animation(.easeIn, value: game)
    }
    
    func createChapterEntrypointView(_ chapter: GameChapter) -> some View {
        Button {
            withAnimation {
                /// Simulate entering the game, playing, and advancing to the next checkpoint.
                /// In case the player is replaying an earlier chapter, the check with `chapter` prevents the game from advancing the checkpoint.
                game.proceedGame(chapter, timePlayed: timePlayedSinceLastSave)
                try? gsm.updateGame(game)
                
                timePlayedSinceLastSave = .zero
            }
        } label: {
            createChapterLabelView(chapter)
                .frame(minHeight: 100)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(game.checkChapterStatus(chapter) == .locked ? true : false)
    }
    
    func createChapterLabelView(_ chapter: GameChapter) -> some View {
        ZStack(alignment: .top) {
            ZStack {
                RoundedRectangle(cornerRadius: 25.0, style: .continuous)
                    .stroke(chapter.color, lineWidth: 5)
                    .fill(fillColor(chapter))
                    .padding(.horizontal)
                
                Text(formatChapterTitle(chapter))
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(textColor(chapter))
            }
            
            createCheckpointIndicatorView(chapter)
        }
    }
    
    func createCheckpointIndicatorView(_ chapter: GameChapter) -> some View {
        Self.createBasicCheckpointIndicatorView(chapter, status: game.checkChapterStatus(chapter))
            .font(.headline)
            .foregroundStyle(textColor(chapter))
            .padding(.top)
    }
    
    static func createBasicCheckpointIndicatorView(_ chapter: GameChapter, status: GameChapter.ChapterStatus) -> some View {
        func indicatorSymbolName(_ index: Int) -> String {
            switch status {
            case .locked:
                return "lock.fill"
            case .completed:
                return "circle.fill"
            case .inProgress(completedCheckpoints: let checkpoints):
                return index <= checkpoints ? "circle.fill" : "circle"
            case .notStarted:
                return "circle"
            }
        }
        
        return HStack {
            ForEach((1...(status == .locked ? 1 : chapter.checkpoints)), id: \.self) { index in
                Image(systemName: indicatorSymbolName(index))
            }
        }
    }
    
    func createFootnotesView() -> some View {
        HStack {
            Spacer()
            VStack {
                Text("Total game play time: \(game.timePlayed.formatted())")
                Text("Save profile created: \(formatRelativeDateString(game.dateStarted))")
                Text("Time since last save: \(timePlayedSinceLastSave.formatted())")
            }
            .font(.monospacedDigit(.footnote)())
            Spacer()
        }
        .onReceive(timer, perform: { _ in
            timePlayedSinceLastSave += .seconds(1)
        })
    }
    
    // MARK: - String formatters
    
    func formatRelativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        
        return formatter.localizedString(for: date, relativeTo: .now)
    }
    
    func formatChapterTitle(_ chapter: GameChapter) -> String {
        switch game.checkChapterStatus(chapter) {
        case .locked:
            return "CHAPTER \(chapter.ordinal)"
        default:
            return "\(chapter.title)"
        }
    }
    
    // MARK: - View styles and modifiers
        
    func fillColor(_ chapter: GameChapter) -> Color {
        switch game.checkChapterStatus(chapter) {
        case .locked:
            return .clear
        case .notStarted:
            return chapter.color.opacity(0.4)
        case .completed:
            return chapter.color
        case .inProgress:
            return chapter.color.opacity(0.8)
        }
    }
    
    func textColor(_ chapter: GameChapter) -> Color {
        chapter <= game.chapter ? .white : Color.primary
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var gameProgress = SaveGame()
    
    return GameView(game: gameProgress)
        .environment(GameSaveModel.shared)
}
