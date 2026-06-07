/*
<samplecode>
  <abstract>
  Concrete data type to represent a saved game and game progression.
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

import Foundation
import os.log

fileprivate extension Logger {
    static let saveGame = Logger(subsystem: Self.loggingSubsystem, category: "SaveGame")
}

@Observable final class SaveGame: Codable, Equatable, Identifiable, Hashable {
    
    // MARK: - Properties
        
    private(set) var chapter: GameChapter
    private(set) var status: GameChapter.ChapterStatus
    
    let dateStarted: Date
    private(set) var timePlayed: Duration
    private(set) var lastPlayed: Date?
        
    var superBigExtraGameSaveData: Data
    
    // MARK: - Init
    
    init() {
        chapter = .night
        status = .notStarted
        lastPlayed = nil
        timePlayed = .zero
        dateStarted = .now
        superBigExtraGameSaveData = (try? Self.generateRandomBytes(Config.superBigExtraGameSaveDataByteSize)) ?? Data()
    }
    
    // MARK: - Codable
    
    /// Custom codable keys and methods are necessary because this class is `@Observable` and works with this sample's SwiftUI views.
    private enum CodingKeys: CodingKey {
        case chapter
        case status
        case dateStarted
        case timePlayed
        case lastPlayed
        case extraData
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        chapter                     = try container.decode(GameChapter.self, forKey: .chapter)
        status                      = try container.decode(GameChapter.ChapterStatus.self, forKey: .status)
        dateStarted                 = try container.decode(Date.self, forKey: .dateStarted)
        timePlayed                  = try container.decode(Duration.self, forKey: .timePlayed)
        lastPlayed                  = try? container.decode(Date.self, forKey: .lastPlayed)
        superBigExtraGameSaveData   = try container.decode(Data.self, forKey: .extraData)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(chapter, forKey: .chapter)
        try container.encode(status, forKey: .status)
        try container.encode(dateStarted, forKey: .dateStarted)
        try container.encode(timePlayed, forKey: .timePlayed)
        try container.encode(lastPlayed, forKey: .lastPlayed)
        try container.encode(superBigExtraGameSaveData, forKey: .extraData)
    }
        
    // MARK: - Equatable
    
    static func == (lhs: SaveGame, rhs: SaveGame) -> Bool {
        return lhs.chapter == rhs.chapter &&
        lhs.status == rhs.status &&
        lhs.dateStarted == rhs.dateStarted &&
        lhs.timePlayed == rhs.timePlayed &&
        lhs.lastPlayed == rhs.lastPlayed
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(chapter)
        hasher.combine(status)
        hasher.combine(dateStarted)
        hasher.combine(timePlayed)
        hasher.combine(lastPlayed)
    }
    
    // MARK: - Update game state
    
    func proceedGame(_ chapter: GameChapter, timePlayed: Duration, proceedAnyway: Bool = false) {
        refreshTimePlayed(timePlayed)
                
        switch checkChapterStatus(chapter) {
        case .locked:
            if proceedAnyway {
                self.status = .inProgress(completedCheckpoints: 0)
                self.chapter = chapter
            } else {
                break
            }
        case .notStarted:
            guard chapter == self.chapter else {
                return
            }
            self.status = .inProgress(completedCheckpoints: 0)
        case .inProgress(let checkpoints):
            if self.chapter.isFinalChapter {
                self.status = .completed
                return
            }
            self.status = .inProgress(completedCheckpoints: checkpoints + 1)
            if checkpoints + 1 == chapter.checkpoints {
                self.chapter = .init(chapter.ordinal + 1)!
                self.status = .notStarted
            }
        case .completed:
            Logger.saveGame.log("Can replay this chapter.")
        }
    }
    
    func saveGameOnDemand(_ currentSessionTimePlayed: Duration) {
        refreshTimePlayed(currentSessionTimePlayed)
    }
    
    func checkChapterStatus(_ chapter: GameChapter) -> GameChapter.ChapterStatus {
        if chapter > self.chapter {
            return .locked
        }
        if chapter < self.chapter {
            return .completed
        }
        return self.status
    }
    
    // MARK: - Private functions
    
    private func refreshTimePlayed(_ duration: Duration) {
        timePlayed += duration
        lastPlayed = .now
    }
}

