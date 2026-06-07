/*
<samplecode>
  <abstract>
  The sample game's chapters.
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
import SwiftUI

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

enum GameChapter: String, CaseIterable, Identifiable, Comparable, Codable {
    
    case night
    case astronomicalTwilight
    case nauticalTwilight
    case civilTwilight
    case day
    
    enum ChapterStatus: Equatable, Hashable, Codable, Comparable {
        
        case locked
        case notStarted
        case inProgress(completedCheckpoints: Int)
        case completed
    }
    
    var color: Color {
#if os(macOS)
        return .init(nsColor: self.platformColor)
#else
        return .init(uiColor: self.platformColor)
#endif
    }
    
    private var platformColor: PlatformColor {
        switch self {
        case .night:
            return #colorLiteral(red: 0.004859850742, green: 0.09608627111, blue: 0.5749928951, alpha: 1)
        case .astronomicalTwilight:
            return #colorLiteral(red: 0.01680417731, green: 0.1983509958, blue: 1, alpha: 1)
        case .nauticalTwilight:
            return #colorLiteral(red: 0, green: 0.3285208941, blue: 0.5748849511, alpha: 1)
        case .civilTwilight:
            return #colorLiteral(red: 1, green: 0.5781051517, blue: 0, alpha: 1)
        case .day:
            return #colorLiteral(red: 0.4620226622, green: 0.8382837176, blue: 1, alpha: 1)
        }
    }
    
    var checkpoints: Int {
        switch self {
        case .night:
            return 2
        case .astronomicalTwilight:
            return 3
        case .nauticalTwilight:
            return 4
        case .civilTwilight:
            return 6
        case .day:
            return 1
        }
    }
    
    var title: String {
        return self.rawValue.replacingOccurrences(of: "T", with: " t")
    }
    
    var isFinalChapter: Bool {
        return self == .day
    }
    
    // MARK: - Helpers and protocols
    
    var id: Self { return self }
    
    init?(_ sequential: Int) {
        self = Self.allCases[sequential - 1]
    }
    
    var ordinal: Self.AllCases.Index {
        return Self.allCases.firstIndex(of: self)! + 1
    }
    
    static func < (lhs: GameChapter, rhs: GameChapter) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }
}
