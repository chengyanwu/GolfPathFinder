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
    
//    private func hmacStringToSign(stringToSign: String, secretSigningKey: String, shortDateString: String) -> String? {
//            let k1 = "AWS4" + secretSigningKey
//            guard let sk1 = try? HMAC(key: [UInt8](k1.utf8), variant: .sha256).authenticate([UInt8](shortDateString.utf8)),
//            let sk2 = try? HMAC(key: sk1, variant: .sha256).authenticate([UInt8]("us-west-1")),
//            let sk3 = try? HMAC(key: sk2, variant: .sha256).authenticate([UInt8]("us-west-1")),
//            let sk4 = try? HMAC(key: sk3, variant: .sha256).authenticate([UInt8]("us-west-1")),
//            let signature = try? HMAC(key: sk4, variant: .sha256).authenticate([UInt8](stringToSign.utf8)) else { return .none }
//        return signature.toHexString()
//    }
    
//    struct course: Hashable, Codable{
//        let name:String
//        let
//    }

    /// Builds the location annotations for a few random objects, scattered across the country
    ///
    /// - Returns: an array of annotation nodes.
    func buildDemoData() -> [LocationAnnotationNode] {
        
        let API_token = "WgB5mUDvCh94P5JGMjoPI2on3vnK7TVh8GOrQDvx"
        let access_key = "AKIAY4WGH3URFU3AQXC3"
        let secret_key = "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"
        
//        let urlString = "https://api.golfbert.com/v1/courses"
        let urlString = "https://api.golfbert.com/v1/courses/1593/holes"
        var urlRequest = URLRequest(url:URL(string: urlString)!)
        
        urlRequest.httpMethod = "GET"
        urlRequest.addValue(API_token, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        try! urlRequest.sign(accessKeyId: access_key, secretAccessKey: secret_key)
//        var flag1_lat: Double = 34.42897256495137
//        var flag1_long: Double = -119.90183651447296
        var flag1_lat: Double = 0
        var flag1_long: Double = 0
        
        var flag2_lat: Double = 34.423493
        var flag2_long: Double = -119.641111
        
        var flag3_lat: Double = 33.998989
        var flag3_long: Double = -119.857081
        
        var flag4_lat: Double = 37.116470
        var flag4_long: Double = -115.452546
        
        let group = DispatchGroup()
        group.enter()
        let task = URLSession.shared.dataTask(with: urlRequest, completionHandler:{
            (data: Data!, response: URLResponse!, error: Error!) -> Void in
            print("enterning url session")
//            group.enter()
            let json = try! JSONDecoder().decode(Root.self, from:data)
            
            flag1_lat = json.resources[0].flagcoords.lat
            flag1_long = json.resources[0].flagcoords.long
            
//            flag2_lat = json.resources[1].flagcoords.lat
//            flag2_long = json.resources[1].flagcoords.long
//
//            flag3_lat = json.resources[2].flagcoords.lat
//            flag3_long = json.resources[2].flagcoords.long
//
//            flag4_lat = json.resources[3].flagcoords.lat
//            flag4_long = json.resources[3].flagcoords.long
            

            print(flag1_lat)
            print(flag1_long)
            
            group.leave()
            print("leaving url session")

        })
        task.resume()
        
        group.wait()
        
        print(flag1_lat)
        print(flag1_long)
        var nodes: [LocationAnnotationNode] = []

        let hole1Layer = CATextLayer()
        hole1Layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hole1Layer.cornerRadius = 4
        hole1Layer.fontSize = 14
        hole1Layer.alignmentMode = .center
        hole1Layer.foregroundColor = UIColor.black.cgColor
        hole1Layer.backgroundColor = UIColor.white.cgColor

        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
            let location2 = CLLocation(latitude: flag1_lat, longitude: flag1_long)
            let distanceInMeters = location1!.distance(from:location2)
            hole1Layer.string = String(format: "Hole 1\nDistance: %.1fm", distanceInMeters)
        }

        let hole1 = buildLayerNode(latitude: flag1_lat, longitude: flag1_long, altitude: 13, layer: hole1Layer)
        nodes.append(hole1)
        
        let hole2Layer = CATextLayer()
        hole2Layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hole2Layer.cornerRadius = 4
        hole2Layer.fontSize = 14
        hole2Layer.alignmentMode = .center
        hole2Layer.foregroundColor = UIColor.black.cgColor
        hole2Layer.backgroundColor = UIColor.white.cgColor

        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
            let location2 = CLLocation(latitude: flag2_lat, longitude: flag2_long)
            let distanceInMeters = location1!.distance(from:location2)
            hole2Layer.string = String(format: "Hole 2\nDistance: %.1fm", distanceInMeters)
        }

        let hole2 = buildLayerNode(latitude: flag2_lat, longitude: flag2_long, altitude: 13, layer: hole2Layer)
        nodes.append(hole2)
        
        let hole3Layer = CATextLayer()
        hole3Layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hole3Layer.cornerRadius = 4
        hole3Layer.fontSize = 14
        hole3Layer.alignmentMode = .center
        hole3Layer.foregroundColor = UIColor.black.cgColor
        hole3Layer.backgroundColor = UIColor.white.cgColor

        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
            let location2 = CLLocation(latitude: flag3_lat, longitude: flag3_long)
            let distanceInMeters = location1!.distance(from:location2)
            hole3Layer.string = String(format: "Hole 3\nDistance: %.1fm", distanceInMeters)
        }

        let hole3 = buildLayerNode(latitude: flag3_lat, longitude: flag3_long, altitude: 13, layer: hole3Layer)
        nodes.append(hole3)
        
        let hole4Layer = CATextLayer()
        hole4Layer.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        hole4Layer.cornerRadius = 4
        hole4Layer.fontSize = 14
        hole4Layer.alignmentMode = .center
        hole4Layer.foregroundColor = UIColor.black.cgColor
        hole4Layer.backgroundColor = UIColor.white.cgColor

        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let location1 = self.sceneLocationView.sceneLocationManager.currentLocation
            let location2 = CLLocation(latitude: flag4_lat, longitude: flag4_long)
            let distanceInMeters = location1!.distance(from:location2)
            hole4Layer.string = String(format: "Hole 4\nDistance: %.1fm", distanceInMeters)
        }

        let hole4 = buildLayerNode(latitude: flag4_lat, longitude: flag4_long, altitude: 13, layer: hole4Layer)
        nodes.append(hole4)
        
        let applePark = buildViewNode(latitude: 37.334807, longitude: -122.009076, altitude: 100, text: "Apple Park")
        nodes.append(applePark)

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
