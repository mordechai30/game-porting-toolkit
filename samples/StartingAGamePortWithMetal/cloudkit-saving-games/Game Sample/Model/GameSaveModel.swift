/*
<samplecode>
  <abstract>
  Data model for how the game manages saves, including saving, loading, and syncing with cloud.
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
    static let gameSaveModel = Logger(subsystem: Self.loggingSubsystem, category: "GameSaveModel")
}

@Observable final class GameSaveModel {
    
    // MARK: - Singleton
    
    static let shared = GameSaveModel()
    
    private init() {
        cloudSaveManager = .init(cloudIdentifier: Config.containerIdentifier,
                                 saveDirectoryURL: Config.saveFolderDirectory,
                                 filter: Config.predicate,
                                 databaseURL: Config.databaseURL)
        
        if cloudSaveManager == nil {
            Logger.gameSaveModel.error("cloudSaveManager is nil.")
        }
    }

    // MARK: - Properties
        
    var saveGameRecords = [SaveGameRecord]()
    
    var cloudSaveManager: CloudSaveManager?
    
    private(set) var syncState: SyncState?
        
    enum SyncState: Identifiable {
        case syncing
        case conflict
        case exception
        
        var id: Self { self }
    }
    
    var cloudConflict: CloudSaveConflict? {
        return cloudSaveManager?.unresolvedConflict
    }
        
    // MARK: - Public functions
    
    func sync() async {
        do {
            guard let cloudSaveManager = cloudSaveManager else {
                Logger.gameSaveModel.log("Skipping sync, because cloudSaveManager is nil.")
                return
            }
            
            syncState = .syncing
            let hasConflict = try await cloudSaveManager.sync()
            if hasConflict {
                syncState = .conflict
            } else {
                syncState = nil
            }
            Logger.gameSaveModel.log("Finished syncing. Conflict: \(hasConflict)")
        } catch {
            syncState = .exception
            Logger.gameSaveModel.error("Could not sync: \(error)")
        }
    }
    
    func resolveWithVersion(_ saveVersion: SaveVersion) async {
        guard let cloudSaveManager = cloudSaveManager else {
            Logger.gameSaveModel.log("Skipping resolution, because cloudSaveManager is nil.")
            return
        }
        
        let locality = saveVersion == .local ? CloudSaveLocalityLocal : CloudSaveLocalityServer
        
        do {
            _ = try await cloudSaveManager.resolveConflict(with: locality)
        } catch {
            Logger.gameSaveModel.error("Could not resolve conflict: \(error)")
        }
    }
    
    func updateGame(_ game: SaveGame) throws {
        /// For simplicity, the slot number and saved game's local identifier are the same, unique, and both are UInt.
        guard let matchingRecord = findGameRecord(game) else {
            Logger.gameSaveModel.error("Save game \(String(describing: game)) not found on update.")
            return
        }
        
        Logger.gameSaveModel.log("Saving game \(matchingRecord.localIdentifier)")
        
        try saveLocalGame(matchingRecord)
        
        Logger.gameSaveModel.log("Saved game \(matchingRecord.localIdentifier)")
        
    }
    
    func deleteGame(_ localIdentifier: SaveGameRecord.LocalIdentifier) async throws {
        /// For simplicity, the slot number, of type UInt, is also the saved game's local identifier, and it is unique for each saved game.
        guard let matchingRecord = saveGameRecords.first(where: { localIdentifier == $0.localIdentifier }) else {
            Logger.gameSaveModel.error("Save game '\(localIdentifier)' not found on delete.")
            return
        }
        
        Logger.gameSaveModel.log("Deleting game \(matchingRecord.localIdentifier)")
        
        matchingRecord.game = .init()
        try deleteSaveFile(at: localIdentifier)
        
    }
    
    func deleteAllSaveGames() async throws {
        for record in saveGameRecords {
            record.game = .init()
            try await deleteGame(record.localIdentifier)
        }
    }
    
    // MARK: - File management
    
    func loadLocalGame() {
        var localGames = [SaveGameRecord]()
        
        for index: UInt in 1...Config.maxSaveGameCount {
            localGames.append(.init(localIdentifier: index, game: .init()))
        }
        
        discoverSaveFiles().forEach { discoveredSaveFile in
            do {
                let record = try loadSaveFile(discoveredSaveFile)
                guard let index = localGames.firstIndex(where: { $0.localIdentifier == record.localIdentifier }) else {
                    Logger.gameSaveModel.error("A save is discovered but has no place for it in the game: \(record.localIdentifier)")
                    return
                }
                localGames[index].game = record.game
            } catch {
                Logger.gameSaveModel.error("\(error)")
            }
        }
        
        saveGameRecords = localGames
    }
    
    func saveLocalGame(_ record: SaveGameRecord) throws {
        try writeSaveFile(content: record.game, to: record.localIdentifier)
    }
    
    // MARK: - Find games
    
    func findGameRecord(_ game: SaveGame) -> SaveGameRecord? {
        saveGameRecords.first(where: { game == $0.game })
    }
    
    func findGameRecord(_ localIdentifier: SaveGameRecord.LocalIdentifier) -> SaveGameRecord? {
        saveGameRecords.first(where: { localIdentifier == $0.localIdentifier })
    }
    
    func findGameIdentifier(_ game: SaveGame) -> SaveGameRecord.LocalIdentifier? {
        findGameRecord(game)?.localIdentifier
    }
    
    // MARK: - Helper error type

    enum GameSaveModelError: Error {
        case saveGameNotFound(String)
        case invalidSaveSlot(String)
        case cannotFindCloudGame(String)
    }
}

