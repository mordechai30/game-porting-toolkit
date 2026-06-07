/*
<samplecode>
  <abstract>
  Data type to represent a saved-game record, including an ID and the saved game.
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

@Observable class SaveGameRecord {
    public typealias LocalIdentifier = UInt
    
    let localIdentifier: LocalIdentifier
    
    var game: SaveGame
    
    internal init(localIdentifier: UInt,
                  game: SaveGame) {
        self.localIdentifier = localIdentifier
        self.game = game
    }
}

// MARK: - Equatable

extension SaveGameRecord: Equatable {
    static func == (lhs: SaveGameRecord, rhs: SaveGameRecord) -> Bool {
        return lhs.localIdentifier == rhs.localIdentifier &&
        lhs.game == rhs.game
    }
}

// MARK: - Identifiable

extension SaveGameRecord: Identifiable {
    var id: LocalIdentifier { localIdentifier }
}
