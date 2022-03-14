//
//  GreenPoint.swift
//  ARKit+CoreLocation
//
//  Created by Kyle Wong on 3/13/22.
//  Copyright © 2022 Project Dent. All rights reserved.
//
import Foundation
import CoreLocation

class GreenPoint {
    var distToTarget: Double
    var distFromStart: Double
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double, start: CLLocation, target: CLLocation) {
        self.lat = lat
        self.lon = lon
        let location = CLLocation(latitude: lat, longitude: lon)
        self.distToTarget = location.distance(from: target)
        self.distFromStart = location.distance(from: start)
    }
}
