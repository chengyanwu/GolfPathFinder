//
//  JSON_Struct.swift
//  ARKit+CoreLocation
//
//  Created by Ian Wu on 2/23/22.
//  Copyright © 2022 Project Dent. All rights reserved.
//

import Foundation

// MARK: - Welcome
struct JSON_Flag: Codable {
    let resources: [Resource]
}

// MARK: - Resource
struct Resource: Codable {
    let id, number, courseid: Int
    let rotation: Double
    let range: Range
    let dimensions: Dimensions
    let vectors: [Vector]
    let flagcoords: Flagcoords
}

// MARK: - Dimensions
struct Dimensions: Codable {
    let width, height: Int
}

// MARK: - Flagcoords
struct Flagcoords: Codable {
    let lat, long: Double
}

// MARK: - Range
struct Range: Codable {
    let x, y: X
}

// MARK: - X
struct X: Codable {
    let min, max: Double
}

// MARK: - Vector
struct Vector: Codable {
    let type: TypeEnum
    let lat, long: Double
}

enum TypeEnum: String, Codable {
    case black = "Black"
    case flag = "Flag"
    case red = "Red"
    case silver = "Silver"
}


//struct JSON_Polygon: Codable {
//    let resources: [Resource2]
//}
//
//// MARK: - Resource
//struct Resource2: Codable {
//    let holeid: Int
//    let surfacetype: Surfacetype
//    let polygon: [Polygon]
//}
//
//// MARK: - Polygon
//struct Polygon: Codable {
//    let lat, long: Double
//}
//
//enum Surfacetype: String, Codable {
//    case fairway = "Fairway"
//    case green = "Green"
//    case sand = "Sand"
//    case woods = "Woods"
//}
