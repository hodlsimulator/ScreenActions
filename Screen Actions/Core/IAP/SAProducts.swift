//
//  SAProducts.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//

import Foundation

enum SAProducts {
    // Exact IDs (verbatim)
    static let proMonthly  = "com.conornolan.Screen-Actions.pro.monthly"
    static let proLifetime = "com.conornolan.Screen-Actions.pro.lifetime"
    static let tipSmall    = "com.conornolan.Screen-Actions.tip.small"
    static let tipMedium   = "com.conornolan.Screen-Actions.tip.medium"
    static let tipLarge    = "com.conornolan.Screen-Actions.tip.large"

    static let all: Set<String> = [
        proMonthly, proLifetime, tipSmall, tipMedium, tipLarge
    ]

    static let proSet: Set<String> = [proMonthly, proLifetime]
}
