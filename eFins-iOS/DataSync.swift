//
//  dataSyncManager.swift
//  eFins-iOS
//
//  Created by Todd Bryan on 3/11/15.
//  Copyright (c) 2015 McClintock Lab. All rights reserved.
//

import Foundation
import Alamofire
import Realm
import SwiftyJSON

private let _mgr = DataSync()

class DataSync {
    
    let periodicSynchronizationInterval : NSTimeInterval = 30.0 //Seconds
    let reachability: Reachability
    var timer: NSTimer = NSTimer()
    var syncInProgress = false
    
    
    init() {
        let uri = NSURL(string: SERVER_ROOT)
        let host = uri?.host ?? ""
        self.reachability = Reachability(hostname: host)
        self.log("Reachability will be measured against " + host)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "reachabilityChanged", name: ReachabilityChangedNotification, object: reachability)
        reachability.startNotifier()
    }
    
    class var manager: DataSync {
        return _mgr
    }
    
    func sync() {
        self.log("Begin Synchronization")
        if ( self.syncInProgress ) {
            self.log("Synchronization already in progress; yielding.")
            return
        }
        let token = NSUserDefaults.standardUserDefaults().stringForKey("SessionToken")
        if (token == nil) {
            self.log("Synchronization not yet possible; no session token; yielding.");
            return
        }
        let prio = DISPATCH_QUEUE_PRIORITY_DEFAULT
        let queue = dispatch_get_global_queue(prio, 0)
        self.syncInProgress = true
        dispatch_async(queue) {
            //self.log("Sync executing on background queue")
            let defaults = NSUserDefaults.standardUserDefaults()
            let usn = defaults.integerForKey("currentUsn")
            let endOfLastSync = defaults.integerForKey("endOfLastSync")
            
            //self.pull( usn, endOfLastSync: endOfLastSync, maxCount: 0)
            self.pull( 0, endOfLastSync: endOfLastSync, maxCount: 0)

            
            dispatch_async(dispatch_get_main_queue()) {
                //Emit UI update event here if needed?
                self.syncInProgress = false
                self.log("Synchronization complete.")
            }
        }
    }
    
    @objc func syncFire(ti: NSTimer) {
        self.sync()
    }
    
    func defaultRealm() -> RLMRealm {
        return RLMRealm.defaultRealm()
    }
    
    func start() {
        self.log("DataSync Manager Starting");
        let dRealm = self.defaultRealm()
        self.log("Default Realm file is: " + dRealm.path)
        self.log("Checking reachability against " + SERVER_ROOT);
        if (self.reachability.isReachable()) {
            self.log("Server " + SERVER_ROOT + " is currently reachable")
            let token = NSUserDefaults.standardUserDefaults().stringForKey("SessionToken")
            if (token != nil) {
                //If connectivity and a token, trigger a sync now.
                self.log("Found a SessionToken: \(token)")
                self.sync()
            }
            self.startPeriodicSyncs()
        } else {
            self.log("Server " + SERVER_ROOT + " is NOT currently reachable")
        }
    }
    
    func startPeriodicSyncs() {
        self.log("Starting periodic synchronization")
        self.timer = NSTimer.scheduledTimerWithTimeInterval(self.periodicSynchronizationInterval, target: self, selector:"syncFire:", userInfo: nil, repeats: true)

    }
    
    func stopPeriodicSyncs() {
        self.log("Stopping periodic synchronization")
        self.timer.invalidate()
    }
    
    @objc func reachabilityChanged() {
        if (self.reachability.isReachable()) {
            self.log("Server became reachable")
            self.startPeriodicSyncs()
        } else {
            self.log("Server became unreachable")
            self.stopPeriodicSyncs()
        }
    }
    
    func log(msg: String) {
        NSLog("DataSync Manager: " + msg)
    }
    
    func pull(currentUsn: Int, endOfLastSync: Int, maxCount: Int ) {
        let afterUsn = NSURLQueryItem(name: "afterUsn", value: "\(currentUsn)")
        let endOfLastSync = NSURLQueryItem(name: "endOfLastSync", value: "\(endOfLastSync)")

        var components = NSURLComponents(string: Urls.sync)!
        components.queryItems = [ afterUsn, endOfLastSync]

        let mutableURLRequest = NSMutableURLRequest(URL: components.URL!)
        mutableURLRequest.HTTPMethod = "GET"
        mutableURLRequest.setValue("Bearer " + NSUserDefaults.standardUserDefaults().stringForKey("SessionToken")! , forHTTPHeaderField: "Authorization")
        self.log("Getting \(Urls.sync)")
        
        Alamofire.request(mutableURLRequest)
            .responseString { (request, response, data, error) in
                println(data)
                if (error != nil) {
                    self.log("Connection Error, Problem connecting to server: \(error). \(response)")
                } else if (response?.statusCode == 404) {
                    self.log("404")
                } else if (response?.statusCode == 401) {
                    self.log("401")
                } else if (response?.statusCode == 403) {
                    self.log("403")
                } else if (response?.statusCode == 204) {
                    self.log("Server reports we are up-to-date")
                } else if response?.statusCode == 200 {
                    self.log("Got reply to sync request: \(data)")
                    let json = JSON(data: data!.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!)
                    self.log(json.stringValue)
                    if(self.digestResults(json) == true) {
                        let defaults = NSUserDefaults.standardUserDefaults()
                        let newUsn = json["highestUsn"].int
                        defaults.setInteger(newUsn!, forKey: "currentUsn")
                        defaults.setInteger(json["timestamp"].int!, forKey: "endOfLastSync")
                        self.log("After a successful sync, setting currentUsn to \(newUsn)")
                    } else {
                        self.log("Failed to digest server results; discarding pulled data")
                    }
                } else {
                    self.log(data?.stringByStandardizingPath ?? "")
                }
        }

        
        
    }
    
    func push() {
        
    }
    
    func digestResults(json: JSON) -> Bool {
        let dRealm = self.defaultRealm()
        dRealm.beginWriteTransaction()
        var newEntities: [RLMObject] = []

        for (key: String, subJson: JSON) in json {
            if(key == "models") {
                for (key: String, modelArrayJson: JSON) in subJson {
                    self.log("Handling \(key)")
                    // This whole switch statement is only needed because we don't have a good way of turning a string into a Swift class yet
                    switch(key) {
                        case "Action":
                            Action.ingest(modelArrayJson)
                        case "Activity":
                            Activity.ingest(modelArrayJson)
                        case "Agency":
                            Agency.ingest(modelArrayJson)
                        case "AgencyVessel":
                            AgencyVessel.ingest(modelArrayJson)
                        case "Catch":
                            Catch.ingest(modelArrayJson)
                        case "ContactType":
                            ContactType.ingest(modelArrayJson)
                        case "EnforcementActionTaken":
                            EnforcementActionTaken.ingest(modelArrayJson)
                        case "EnforcementActionType":
                            EnforcementActionType.ingest(modelArrayJson)
                        case "Fishery":
                            Fishery.ingest(modelArrayJson)
                        case "FreeTextCrew":
                            FreeTextCrew.ingest(modelArrayJson)
                        case "PatrolLog":
                            PatrolLog.ingest(modelArrayJson)
                        case "Person":
                            Person.ingest(modelArrayJson)
                        case "Photo":
                            Photo.ingest(modelArrayJson)
                        case "Port":
                            Port.ingest(modelArrayJson)
                        case "RegulatoryCode":
                            RegulatoryCode.ingest(modelArrayJson)
                        case "Species":
                            Species.ingest(modelArrayJson)
                        case "User":
                            User.ingest(modelArrayJson)
                        case "Vessel":
                            Vessel.ingest(modelArrayJson)
                        case "VesselType":
                            VesselType.ingest(modelArrayJson)
                        case "ViolationType":
                            ViolationType.ingest(modelArrayJson)
                        default:
                            self.log("Unknown/unimplemented model key \(key) in server json")
                    }
                }
            }
        }
        for (key: String, subJson: JSON) in json {
            if(key == "models") {
                for (key: String, modelArrayJson: JSON) in subJson {
                    self.log("Associating \(key)")
                    // This whole switch statement is only needed because we don't have a good way of turning a string into a Swift class yet
                    switch(key) {
                        case "Action":
                            Action.setRelationships(modelArrayJson)
                        case "Activity":
                            Activity.setRelationships(modelArrayJson)
                        case "Agency":
                            Agency.setRelationships(modelArrayJson)
                        case "AgencyVessel":
                            AgencyVessel.setRelationships(modelArrayJson)
                      
                        case "User":
                            User.setRelationships(modelArrayJson)
                        default:
                            self.log("SetRelationships: Unknown/unimplemented model key \(key) in server json")
                    }
                }
            }
        }
        
        self.setRelationships(json["relations"])


        dRealm.commitWriteTransaction()

        return true
    }
    
    
    func setRelationships(rJson: JSON) -> Bool {
        self.log("Setting many-to-many relations")
        let dRealm = self.defaultRealm()
        
        for (relationName: String, aJson: JSON) in rJson {
            let source = aJson["sourceModel"].stringValue
            let target = aJson["targetModel"].stringValue
            self.log("\(relationName) is a many-to-many between \(source) and \(target) ")
            var sourceModel = Models[source]
            var targetModel = Models[target]
            var sourceSchema = dRealm.schema.schemaForClassName(source)
            var targetSchema = dRealm.schema.schemaForClassName(target)
            if (sourceSchema == nil) {
                self.log("Problem: no Realm schema found for JSON object named \(source)")
            }
            if (targetSchema == nil) {
                self.log("Problem: no Realm schema found for JSON object named \(target)")
            }
            
            var found = 0
            for p in sourceSchema.properties {
                let property: RLMProperty = p as! RLMProperty
                if property.type == RLMPropertyType.Array && property.objectClassName == target {
                    self.log("Found an array property named \(property.name) on \(source)")
                    found++
                }
            }
            for p in targetSchema.properties {
                let property: RLMProperty = p as! RLMProperty
                if property.type == RLMPropertyType.Array && property.objectClassName == source {
                    self.log("Found an array property named \(property.name) on \(target)")
                    found++
                }
            }
            if(found == 0) {
                self.log("Oh shit; the JSON expected a relationship but we didn't find one in the local (Realm) schema")
            } else if(found > 1) {
                self.log("Oops, we have multiple choices for an association")
            }
            
            // Now, check the two schemas.  We need to make sure that one and only one of them has an array referring to the other.
            // Note that the array might be named after the referred-to model, or it might be aliased to something else (there might
            // be several referential arrays in one model to another model).  So we need to distinguish between them via the relation name given by the server.

        }
        return(true)
    }
    
}
