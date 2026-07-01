//
//  Item.swift
//  leafy
//
//  Created by IsaacHuo on 2026/4/21.
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
