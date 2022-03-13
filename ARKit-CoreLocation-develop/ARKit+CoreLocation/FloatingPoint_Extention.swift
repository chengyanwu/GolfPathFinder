//
//  FloatingPoint+Extension.swift
//  ARKit+CoreLocation
//
//  Created by Kyle Wong on 3/9/22.
//  Copyright © 2022 Project Dent. All rights reserved.
//
import Foundation

extension FloatingPoint {
    func toRadians() -> Self {
        return self * .pi / 180
    }
    
    func toDegrees() -> Self {
        return self * 180 / .pi
    }
}
