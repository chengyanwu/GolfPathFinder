//
//  POIViewController.swift
//  ARKit+CoreLocation
//
//  Created by Andrew Hart on 02/07/2017.
//  Copyright © 2017 Project Dent. All rights reserved.
//

import ARCL
import ARKit
import MapKit
import SceneKit
import UIKit
import CryptoSwift
import CoreLocation
//import AwsSign

@available(iOS 11.0, *)
/// Displays Points of Interest in ARCL
class POIViewController: UIViewController {
    @IBOutlet var mapView: MKMapView!
    @IBOutlet var infoLabel: UILabel!
    @IBOutlet weak var nodePositionLabel: UILabel!

    @IBOutlet var contentView: UIView!
    let sceneLocationView = SceneLocationView()

    var userAnnotation: MKPointAnnotation?
    var locationEstimateAnnotation: MKPointAnnotation?

    var updateUserLocationTimer: Timer?
    var updateInfoLabelTimer: Timer?

    var centerMapOnUserLocation: Bool = true
    var routes: [MKRoute]?

    var showMap = false {
        didSet {
            guard let mapView = mapView else {
                return
            }
            mapView.isHidden = !showMap
        }
    }
    

    /// Whether to display some debugging data
    /// This currently displays the coordinate of the best location estimate
    /// The initial value is respected
    let displayDebugging = false

    let adjustNorthByTappingSidesOfScreen = false
    let addNodeByTappingScreen = true
    
    var heading: Double! = 0.0
    var distance: Float! = 0.0 {
        didSet {
//            setStatusText()
        }
    }
    var status: String! {
        didSet {
//            setStatusText()
        }
    }
    
    var modelNode:SCNNode!
    let rooteNodeName = "Object-1"
    var originalTransform:SCNMatrix4!
    
    var userLocation:CLLocation!

    class func loadFromStoryboard() -> POIViewController {
        return UIStoryboard(name: "Main", bundle: nil)
            .instantiateViewController(withIdentifier: "ARCLViewController") as! POIViewController
        // swiftlint:disable:previous force_cast
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // swiftlint:disable:next discarded_notification_center_observer
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil,
                                               queue: nil) { [weak self] _ in
                                                self?.pauseAnimation()
        }
        // swiftlint:disable:next discarded_notification_center_observer
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil,
                                               queue: nil) { [weak self] _ in
                                                self?.restartAnimation()
        }

        updateInfoLabelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateInfoLabel()
        }

        // Set to true to display an arrow which points north.
        // Checkout the comments in the property description and on the readme on this.
//        sceneLocationView.orientToTrueNorth = false
//        sceneLocationView.locationEstimateMethod = .coreLocationDataOnly

        sceneLocationView.showAxesNode = true
        sceneLocationView.showFeaturePoints = displayDebugging
        sceneLocationView.locationNodeTouchDelegate = self
//        sceneLocationView.delegate = self // Causes an assertionFailure - use the `arViewDelegate` instead:
        sceneLocationView.arViewDelegate = self
        sceneLocationView.locationNodeTouchDelegate = self

        // Now add the route or location annotations as appropriate
        addSceneModels()

        contentView.addSubview(sceneLocationView)
        sceneLocationView.frame = contentView.bounds

        mapView.isHidden = !showMap

        if showMap {
            updateUserLocationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.updateUserLocation()
            }

            routes?.forEach { mapView.addOverlay($0.polyline) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        restartAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        print(#function)
        pauseAnimation()
        super.viewWillDisappear(animated)
    }

    func pauseAnimation() {
        print("pause")
        sceneLocationView.pause()
    }

    func restartAnimation() {
        print("run")
        sceneLocationView.run()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneLocationView.frame = contentView.bounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first,
            let view = touch.view else { return }

        if mapView == view || mapView.recursiveSubviews().contains(view) {
            centerMapOnUserLocation = false
        } else {
            let location = touch.location(in: self.view)

            if location.x <= 40 && adjustNorthByTappingSidesOfScreen {
                print("left side of the screen")
                sceneLocationView.moveSceneHeadingAntiClockwise()
            } else if location.x >= view.frame.size.width - 40 && adjustNorthByTappingSidesOfScreen {
                print("right side of the screen")
                sceneLocationView.moveSceneHeadingClockwise()
            } else if addNodeByTappingScreen {
                let image = UIImage(named: "pin")!
                let annotationNode = LocationAnnotationNode(location: nil, image: image)
                annotationNode.scaleRelativeToDistance = false
                annotationNode.scalingScheme = .normal
                DispatchQueue.main.async {
                    // If we're using the touch delegate, adding a new node in the touch handler sometimes causes a freeze.
                    // So defer to next pass.
                    self.sceneLocationView.addLocationNodeForCurrentPosition(locationNode: annotationNode)
                }
            }
        }
    }
}

// MARK: - MKMapViewDelegate

@available(iOS 11.0, *)
extension POIViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.lineWidth = 3
        renderer.strokeColor = UIColor.blue.withAlphaComponent(0.5)

        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation),
           let pointAnnotation = annotation as? MKPointAnnotation else { return nil }

        let marker = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)

        if pointAnnotation == self.userAnnotation {
            marker.displayPriority = .required
            marker.glyphImage = UIImage(named: "user")
        } else {
            marker.displayPriority = .required
            marker.markerTintColor = UIColor(hue: 0.267, saturation: 0.67, brightness: 0.77, alpha: 1.0)
            marker.glyphImage = UIImage(named: "compass")
        }

        return marker
    }
}

// MARK: - Implementation

@available(iOS 11.0, *)
extension POIViewController {

    /// Adds the appropriate ARKit models to the scene.  Note: that this won't
    /// do anything until the scene has a `currentLocation`.  It "polls" on that
    /// and when a location is finally discovered, the models are added.
    func addSceneModels() {
        // 1. Don't try to add the models to the scene until we have a current location
        guard sceneLocationView.sceneLocationManager.currentLocation != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.addSceneModels()
            }
            return
        }

        let box = SCNBox(width: 1, height: 0.2, length: 5, chamferRadius: 0.25)
        box.firstMaterial?.diffuse.contents = UIColor.gray.withAlphaComponent(0.5)

        // 2. If there is a route, show that
        if let routes = routes {
            sceneLocationView.addRoutes(routes: routes) { distance -> SCNBox in
                let box = SCNBox(width: 1.75, height: 0.5, length: distance, chamferRadius: 0.25)

//                // Option 1: An absolutely terrible box material set (that demonstrates what you can do):
//                box.materials = ["box0", "box1", "box2", "box3", "box4", "box5"].map {
//                    let material = SCNMaterial()
//                    material.diffuse.contents = UIImage(named: $0)
//                    return material
//                }

                // Option 2: Something more typical
                box.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.7)
                return box
            }
        } else {
            // 3. If not, then show the
            buildDemoData().forEach {
                sceneLocationView.addLocationNodeWithConfirmedLocation(locationNode: $0)
            }
        }

        // There are many different ways to add lighting to a scene, but even this mechanism (the absolute simplest)
        // keeps 3D objects fron looking flat
        sceneLocationView.autoenablesDefaultLighting = true

    }
    

    
    struct coor{
        var lat = 0.0
        var long = 0.0
    }
    
    /// Builds the location annotations for a few random objects, scattered across the country
    ///
    /// - Returns: an array of annotation nodes.
    func buildDemoData() -> [LocationAnnotationNode] {
        
        let API_token = "WgB5mUDvCh94P5JGMjoPI2on3vnK7TVh8GOrQDvx"
        let access_key = "AKIAY4WGH3URFU3AQXC3"
        let secret_key = "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"
        
//        let urlString = "https://api.golfbert.com/v1/courses"
        let urlString_flag = "https://api.golfbert.com/v1/courses/1593/holes"
        let urlString_polygon1 = "https://api.golfbert.com/v1/holes/67111/polygons"
        let urlString_polygon2 = "https://api.golfbert.com/v1/holes/67112/polygons"
        
        var urlRequest = URLRequest(url:URL(string: urlString_flag)!)
        urlRequest.httpMethod = "GET"
        urlRequest.addValue(API_token, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        try! urlRequest.sign(accessKeyId: access_key, secretAccessKey: secret_key)
        
        var flag1_coor = coor()
        var flag1_bunkers: [coor] = []
        var flag1_greens: [coor] = []
        var flag1_fairways: [coor] = []
        
        var flag2_coor = coor(lat: 34.413367, long: -119.844813)
        var flag2_bunkers: [coor] = []
        var flag2_greens: [coor] = []
        var flag2_fairways: [coor] = []
        
        var flag3_coor = coor(lat: 34.404868, long: -119.844519)
        var flag3_bunkers: [coor] = []
        var flag3_greens: [coor] = []
        var flag3_fairways: [coor] = []
        
        var flag4_coor = coor(lat: 34.428259, long: -119.850368)
        var flag4_bunkers: [coor] = []
        var flag4_greens: [coor] = []
        var flag4_fairways: [coor] = []
        
        let group = DispatchGroup()
        group.enter()
        let task1 = URLSession.shared.dataTask(with: urlRequest, completionHandler:{
            (data: Data!, response: URLResponse!, error: Error!) -> Void in
            print("enterning url session 1")
//            group.enter()
            let json = try! JSONDecoder().decode(JSON_Flag.self, from:data)
            
            
            flag1_coor.lat = json.resources[0].flagcoords.lat
            flag1_coor.long = json.resources[0].flagcoords.long
            
//            flag2_coor.lat = json.resources[1].flagcoords.lat
//            flag2_coor.long = json.resources[1].flagcoords.long
//
//            flag3_coor.lat = json.resources[2].flagcoords.lat
//            flag3_coor.long = json.resources[2].flagcoords.long
//
//            flag4_lat = json.resources[3].flagcoords.lat
//            flag4_long = json.resources[3].flagcoords.long
            

            print(flag1_coor)
            
            
            print("leaving url session 1")
            group.leave()

        }).resume()
        
        var urlRequest2 = URLRequest(url:URL(string: urlString_polygon1)!)
        urlRequest2.httpMethod = "GET"
        urlRequest2.addValue(API_token, forHTTPHeaderField: "x-api-key")
        urlRequest2.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        try! urlRequest2.sign(accessKeyId: access_key, secretAccessKey: secret_key)
        group.enter()
        let task2 = URLSession.shared.dataTask(with: urlRequest2, completionHandler:{
            (data: Data!, response: URLResponse!, error: Error!) -> Void in
            print("enterning url session 2")
            let json = try! JSONDecoder().decode(JSONPoly.self, from:data)
            
            var lat = 0.0
            var long = 0.0
            var count = 0.0
            var coor_tmp = coor()
//            for resource in json.resources{
//                if(resource.surfacetype == Surfacetype.sand){
//                    for poly in resource.polygon{
//                        lat += poly.lat
//                        long += poly.long
//                        count += 1
//                    }
//                    coor_tmp.lat = lat / count
//                    coor_tmp.long = long / count
//                    flag1_bunkers.append(coor_tmp)
//                }
//            }
            for poly in json.resources[0].polygon{
                flag1_greens.append(coor(lat: poly.lat, long: poly.long))
            }
            for poly in json.resources[1].polygon{
                flag1_fairways.append(coor(lat: poly.lat, long: poly.long))
            }
            flag1_bunkers.append(coor(lat: 34.383622, long: -119.817028))
            flag1_bunkers.append(coor(lat: 34.376743, long: -119.851897))
            flag1_bunkers.append(coor(lat: 34.375485, long: -119.890519))
            flag1_bunkers.append(coor(lat: 34.395056, long: -119.934223))
            
            print(flag1_bunkers)
            
            group.leave()
            print("leaving url session 2")

        }).resume()
        
        var urlRequest3 = URLRequest(url:URL(string: urlString_polygon2)!)
        urlRequest3.httpMethod = "GET"
        urlRequest3.addValue(API_token, forHTTPHeaderField: "x-api-key")
        urlRequest3.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        try! urlRequest3.sign(accessKeyId: access_key, secretAccessKey: secret_key)
        
        group.enter()
        let task3 = URLSession.shared.dataTask(with: urlRequest3, completionHandler:{
            (data: Data!, response: URLResponse!, error: Error!) -> Void in
            print("enterning url session 3")
            let json = try! JSONDecoder().decode(JSONPoly.self, from:data)
            
            var lat = 0.0
            var long = 0.0
            var count = 0.0
            var coor_tmp = coor()
            for resource in json.resources{
                if(resource.surfacetype == Surfacetype.sand){
                    for poly in resource.polygon{
                        lat += poly.lat
                        long += poly.long
                        count += 1
                    }
                    coor_tmp.lat = lat / count
                    coor_tmp.long = long / count
                    flag2_bunkers.append(coor_tmp)
                }
            }
            
            for poly in json.resources[0].polygon{
                flag2_greens.append(coor(lat: poly.lat, long: poly.long))
            }
            for poly in json.resources[1].polygon{
                flag2_fairways.append(coor(lat: poly.lat, long: poly.long))
            }
            
            print(flag2_bunkers)
            
            group.leave()
            print("leaving url session 3")

        }).resume()
        
        group.wait()
        print("All url session ended")
        
        
        // Initilaizing LAN List
        var nodes: [LocationAnnotationNode] = []
        var layers: [CATextLayer] = []
        
        // Creating template for distance-text overlay template
        let distance_layer = CATextLayer()
        distance_layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        distance_layer.cornerRadius = 4
        distance_layer.fontSize = 14
        distance_layer.alignmentMode = .center
        distance_layer.foregroundColor = UIColor.black.cgColor
        distance_layer.backgroundColor = UIColor.white.cgColor

        
        // Creating Hole 1 Node
        let hole1Layer = CATextLayer()
        hole1Layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hole1Layer.cornerRadius = 4
        hole1Layer.fontSize = 14
        hole1Layer.alignmentMode = .center
        hole1Layer.foregroundColor = UIColor.black.cgColor
        hole1Layer.backgroundColor = UIColor.white.cgColor
        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
            let location2 = CLLocation(latitude: flag1_coor.lat, longitude: flag1_coor.long)
            let distanceInMeters = location1!.distance(from:location2)
            hole1Layer.string = String(format: "Flag 1\nDistance: %.1fm", distanceInMeters)
        }
        layers.append(hole1Layer)
        var hole1 = buildLayerNode(latitude: flag1_coor.lat, longitude: flag1_coor.long, altitude: 20, layer: hole1Layer)
        nodes.append(hole1)
        hole1 = buildNode(latitude: flag1_coor.lat, longitude: flag1_coor.long, altitude: 200, imageName: "flag1")
        nodes.append(hole1)
        
        for (idx, bunker) in flag1_bunkers.enumerated(){
            let layer = CATextLayer()
            layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
            layer.cornerRadius = 4
            layer.fontSize = 14
            layer.alignmentMode = .center
            layer.foregroundColor = UIColor.black.cgColor
            layer.backgroundColor = UIColor.white.cgColor
            let time = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
                let location2 = CLLocation(latitude: bunker.lat, longitude: bunker.long)
                let distanceInMeters = location1!.distance(from:location2)
                layer.string = String(format: "Bunker \(idx)\nDistance: %.1fm", distanceInMeters)
            }
            layers.append(layer)
            hole1 = buildLayerNode(latitude: bunker.lat, longitude: bunker.long, altitude: 20, layer: layer)
            nodes.append(hole1)
            hole1 = buildNode(latitude: bunker.lat, longitude: bunker.long, altitude: 100, imageName: "bunker")
            nodes.append(hole1)
        }
        
        // Creating Hole 2 Node
//        let hole2Layer = distance_layer
//
//        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
//            let location2 = CLLocation(latitude: flag2_coor.lat, longitude: flag2_coor.long)
//            let distanceInMeters = location1!.distance(from:location2)
//            hole2Layer.string = String(format: "Flag 2\nDistance: %.1fm", distanceInMeters)
//        }
//        var hole2 = buildLayerNode(latitude: flag2_coor.lat, longitude: flag2_coor.long, altitude: 10, layer: hole2Layer)
//        layers.append(hole2Layer)
//        nodes.append(hole2)
//        hole2 = buildNode(latitude: flag2_coor.lat, longitude: flag2_coor.long, altitude: 10, imageName: "flag2")
//        nodes.append(hole2)
//
//        for (idx, bunker) in flag2_bunkers.enumerated(){
//            let layer = CATextLayer()
//            layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
//            layer.cornerRadius = 4
//            layer.fontSize = 14
//            layer.alignmentMode = .center
//            layer.foregroundColor = UIColor.black.cgColor
//            layer.backgroundColor = UIColor.white.cgColor
//            let time = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//                let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
//                let location2 = CLLocation(latitude: bunker.lat, longitude: bunker.long)
//                let distanceInMeters = location1!.distance(from:location2)
//                layer.string = String(format: "Bunker \(idx)\nDistance: %.1fm", distanceInMeters)
//            }
//            layers.append(layer)
//            hole2 = buildLayerNode(latitude: bunker.lat, longitude: bunker.long, altitude: 20, layer: layer)
//            nodes.append(hole2)
//        }
        
        // Creating Hole 3 Node
//        let hole3Layer = distance_layer
//
//        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
//            let location2 = CLLocation(latitude: flag3_coor.lat, longitude: flag3_coor.long)
//            let distanceInMeters = location1!.distance(from:location2)
//            hole3Layer.string = String(format: "Flag 2\nDistance: %.1fm", distanceInMeters)
//        }
//        var hole3 = buildLayerNode(latitude: flag3_coor.lat, longitude: flag3_coor.long, altitude: 10, layer: hole2Layer)
//        layers.append(hole3Layer)
//        nodes.append(hole3)
//        hole3 = buildNode(latitude: flag3_coor.lat, longitude: flag3_coor.long, altitude: 10, imageName: "flag3")
//        nodes.append(hole3)
//
//        for (idx, bunker) in flag3_bunkers.enumerated(){
//            let layer = CATextLayer()
//            layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
//            layer.cornerRadius = 4
//            layer.fontSize = 14
//            layer.alignmentMode = .center
//            layer.foregroundColor = UIColor.black.cgColor
//            layer.backgroundColor = UIColor.white.cgColor
//            let time = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
//                let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
//                let location2 = CLLocation(latitude: bunker.lat, longitude: bunker.long)
//                let distanceInMeters = location1!.distance(from:location2)
//                layer.string = String(format: "Bunker \(idx)\nDistance: %.1fm", distanceInMeters)
//            }
//            layers.append(layer)
//            hole3 = buildLayerNode(latitude: bunker.lat, longitude: bunker.long, altitude: 20, layer: layer)
//            nodes.append(hole3)
//        }

        return nodes

    }

    @objc
    func updateUserLocation() {
        guard let currentLocation = sceneLocationView.sceneLocationManager.currentLocation else {
            return
        }

        DispatchQueue.main.async { [weak self ] in
            guard let self = self else {
                return
            }

            if self.userAnnotation == nil {
                self.userAnnotation = MKPointAnnotation()
                self.mapView.addAnnotation(self.userAnnotation!)
            }

            UIView.animate(withDuration: 0.5, delay: 0, options: .allowUserInteraction, animations: {
                self.userAnnotation?.coordinate = currentLocation.coordinate
            }, completion: nil)

            if self.centerMapOnUserLocation {
                UIView.animate(withDuration: 0.45,
                               delay: 0,
                               options: .allowUserInteraction,
                               animations: {
                                self.mapView.setCenter(self.userAnnotation!.coordinate, animated: false)
                }, completion: { _ in
                    self.mapView.region.span = MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
                })
            }

            if self.displayDebugging {
                if let bestLocationEstimate = self.sceneLocationView.sceneLocationManager.bestLocationEstimate {
                    if self.locationEstimateAnnotation == nil {
                        self.locationEstimateAnnotation = MKPointAnnotation()
                        self.mapView.addAnnotation(self.locationEstimateAnnotation!)
                    }
                    self.locationEstimateAnnotation?.coordinate = bestLocationEstimate.location.coordinate
                } else if self.locationEstimateAnnotation != nil {
                    self.mapView.removeAnnotation(self.locationEstimateAnnotation!)
                    self.locationEstimateAnnotation = nil
                }
            }
        }
    }

    @objc
    func updateInfoLabel() {
        if let position = sceneLocationView.currentScenePosition {
            infoLabel.text = " x: \(position.x.short), y: \(position.y.short), z: \(position.z.short)\n"
        }

        if let eulerAngles = sceneLocationView.currentEulerAngles {
            infoLabel.text!.append(" Euler x: \(eulerAngles.x.short), y: \(eulerAngles.y.short), z: \(eulerAngles.z.short)\n")
        }

        if let eulerAngles = sceneLocationView.currentEulerAngles,
            let heading = sceneLocationView.sceneLocationManager.locationManager.heading,
            let headingAccuracy = sceneLocationView.sceneLocationManager.locationManager.headingAccuracy {
            let yDegrees = (((0 - eulerAngles.y.radiansToDegrees) + 360).truncatingRemainder(dividingBy: 360) ).short
            infoLabel.text!.append(" Heading: \(yDegrees)° • \(Float(heading).short)° • \(headingAccuracy)°\n")
        }

        let comp = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: Date())
        if let hour = comp.hour, let minute = comp.minute, let second = comp.second, let nanosecond = comp.nanosecond {
            let nodeCount = "\(sceneLocationView.sceneNode?.childNodes.count.description ?? "n/a") ARKit Nodes"
            infoLabel.text!.append(" \(hour.short):\(minute.short):\(second.short):\(nanosecond.short3) • \(nodeCount)")
        }
    }

    func buildNode(latitude: CLLocationDegrees, longitude: CLLocationDegrees,
                   altitude: CLLocationDistance, imageName: String) -> LocationAnnotationNode {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let location = CLLocation(coordinate: coordinate, altitude: altitude)
        let image = UIImage(named: imageName)!
        return LocationAnnotationNode(location: location, image: image)
    }

    func buildViewNode(latitude: CLLocationDegrees, longitude: CLLocationDegrees,
                       altitude: CLLocationDistance, text: String) -> LocationAnnotationNode {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let location = CLLocation(coordinate: coordinate, altitude: altitude)
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        label.text = text
        label.backgroundColor = .green
        label.textAlignment = .center
        return LocationAnnotationNode(location: location, view: label)
    }

    func buildLayerNode(latitude: CLLocationDegrees, longitude: CLLocationDegrees,
                        altitude: CLLocationDistance, layer: CALayer) -> LocationAnnotationNode {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let location = CLLocation(coordinate: coordinate, altitude: altitude)
        return LocationAnnotationNode(location: location, layer: layer)
    }
    
    func calculateHeading(curLocation: CLLocation, targetLocation: CLLocation) -> Float {
        let curLat = curLocation.coordinate.latitude
        let curLon = curLocation.coordinate.longitude
        let tarLat = targetLocation.coordinate.latitude
        let tarLon = targetLocation.coordinate.longitude
        
        let X = cos(tarLat) * sin(tarLon - curLon)
        let Y = cos(curLat) * sin(tarLat) - sin(curLat) * cos(tarLat) * cos(tarLon - curLon)
        
        let bearing = Float(atan2(X, Y)).toDegrees()
        
        return bearing
    }
        
    func updateArcLocation(latitude: CLLocationDegrees, longitude: CLLocationDegrees,
                                altitude: CLLocationDistance) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        

        let curLocation = self.sceneLocationView.sceneLocationManager.currentLocation
                
        
        print("---------------")
        
        let distance = curLocation?.distance(from: location)
        
        print(calculateHeading(curLocation: curLocation!, targetLocation: location))
    
        let bearing = calculateHeading(curLocation: curLocation!, targetLocation: location)
        self.userLocation = curLocation
        
        if self.modelNode == nil {
//            let modelScene = SCNScene(named: "art.scnassets/arrow.dae")!
//            self.modelNode = modelScene.rootNode.childNode(withName: rooteNodeName, recursively: true)
//            let (minBox, maxBox) = self.modelNode.boundingBox
//            self.modelNode.pivot = SCNMatrix4MakeTranslation(0, (maxBox.y - minBox.y) / 2, 0)
////
//            let rotation = SCNMatrix4MakeRotation(Float(bearing + 90).toRadians(), 0, 1, 0)
//            self.modelNode.transform = SCNMatrix4Mult(self.modelNode.transform, rotation)
//
//            self.modelNode.scale = SCNVector3(x: 0.001, y: 0.001, z: 0.001)
//            self.originalTransform = self.modelNode.transform
//
////            positionModel(location)
//
//            sceneLocationView.scene.rootNode.addChildNode(self.modelNode)
//            distance = 10.0
            let arcDist = min(distance!, 400)
            
            let arcStartX = 0.5
            let arcStartY = -0.5
            let controlHeight = (arcDist / 2) * tan(35)
            
            
            let path = UIBezierPath()
            path.move(to: CGPoint(x: arcStartX, y: arcStartY))
            path.addQuadCurve(to: CGPoint(x: arcStartX + arcDist, y: arcStartY), controlPoint: CGPoint(x: arcStartX + (arcDist / 2), y: controlHeight))
            path.addLine(to: CGPoint(x: arcStartX + arcDist - 0.01, y: arcStartY))
            path.addQuadCurve(to: CGPoint(x: arcStartX + 0.01, y: arcStartY), controlPoint: CGPoint(x: arcStartX + (arcDist / 2), y: controlHeight - 0.02))
            path.close()

            path.flatness = 0.0003

            let shape = SCNShape(path: path, extrusionDepth: 0.000438596 * arcDist + 0.0245614)
            let color = #colorLiteral(red: 1, green: 0.08143679053, blue: 0.3513627648, alpha: 0.8459555697)
            shape.firstMaterial?.diffuse.contents = color
    //        shape.chamferRadius = 0.1

            let arcNode = SCNNode(geometry: shape)

//            arcNode.position.z = -1
//            arcNode.position.y = 0.5
//            arcNode.position.x = 0.5
//            arcNode.pivot = SCNMatrix4MakeTranslation(1, 0.2, 0)
            self.modelNode = arcNode

//            arcNode.eulerAngles.y = (.pi/2)
            let rotation = SCNMatrix4MakeRotation(Float(bearing + 90).toRadians(), 0, 1, 0)
            self.modelNode.transform = SCNMatrix4Mult(self.modelNode.transform, rotation)

            self.originalTransform = self.modelNode.transform

//            positionModel(location)
            sceneLocationView.scene.rootNode.addChildNode(arcNode)
            
        } else {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.0
            
//            positionModel(location)
            
            SCNTransaction.commit()
        }
        
        
    }

}

// MARK: - LNTouchDelegate
@available(iOS 11.0, *)
extension POIViewController: LNTouchDelegate {

    func annotationNodeTouched(node: AnnotationNode) {
        if let node = node.parent as? LocationNode {
            let coords = "\(node.location.coordinate.latitude.short)° \(node.location.coordinate.longitude.short)°"
            let altitude = "\(node.location.altitude.short)m"
            let tag = node.tag ?? ""
            nodePositionLabel.text = " Annotation node at \(coords), \(altitude) - \(tag)"
        }
    }

    func locationNodeTouched(node: LocationNode) {
        print("Location node touched - tag: \(node.tag ?? "")")
        let coords = "\(node.location.coordinate.latitude.short)° \(node.location.coordinate.longitude.short)°"
        let altitude = "\(node.location.altitude.short)m"
        let tag = node.tag ?? ""
        nodePositionLabel.text = " Location node at \(coords), \(altitude) - \(tag)"
    }

}

// MARK: - Helpers

extension DispatchQueue {
    func asyncAfter(timeInterval: TimeInterval, execute: @escaping () -> Void) {
        self.asyncAfter(
            deadline: DispatchTime.now() + Double(Int64(timeInterval * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
            execute: execute)
    }
}

extension UIView {
    func recursiveSubviews() -> [UIView] {
        var recursiveSubviews = self.subviews

        subviews.forEach { recursiveSubviews.append(contentsOf: $0.recursiveSubviews()) }

        return recursiveSubviews
    }
}
