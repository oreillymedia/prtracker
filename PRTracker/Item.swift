//
//  Item.swift
//  PRTracker
//
//  Created by Matt Blackmon on 4/27/26.
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
