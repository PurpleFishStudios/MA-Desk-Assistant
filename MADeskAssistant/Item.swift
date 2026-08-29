//
//  Item.swift
//  MADeskAssistant
//
//  Created by Sebastian Esquerra on 8/29/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
