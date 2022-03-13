//
//  JSON_Poly.swift
//  ARKit+CoreLocation
//
//  Created by Ian Wu on 3/10/22.
//  Copyright © 2022 Project Dent. All rights reserved.
// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let jSONPoly = try? newJSONDecoder().decode(JSONPoly.self, from: jsonData)
import Foundation

// MARK: - JSONPoly
struct JSONPoly: Codable {
    let resources: [Resource2]
}

// MARK: - Resource
struct Resource2: Codable {
    let holeid: Int
    let surfacetype: Surfacetype
    let polygon: [Polygon]
}

// MARK: - Polygon
struct Polygon: Codable {
    let lat, long: Double
}

enum Surfacetype: String, Codable {
    case fairway = "Fairway"
    case green = "Green"
    case sand = "Sand"
    case woods = "Woods"
}
