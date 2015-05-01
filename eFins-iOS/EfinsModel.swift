//
//  efinsModel.swift
//  eFins-iOS
//
//  Created by Todd Bryan on 3/25/15.
//  Copyright (c) 2015 McClintock Lab. All rights reserved.
//

import Foundation
import Realm
import SwiftyJSON

class EfinsModel : RLMObject {
    dynamic var id = NSUUID.init().UUIDString
    dynamic var localId = NSUUID.init().UUIDString
    dynamic var usn : Int = -1
    dynamic var createdAt : NSDate = NSDate(timeIntervalSinceNow: 0)
    dynamic var updatedAt : NSDate = NSDate(timeIntervalSinceNow: 0)  // there are no hooks in Realm yet, so we can't really update this automatically as the object is updated
    dynamic var dirty = true
    
    override class func primaryKey() -> String {
        return "id"
    }
    
    class func ingest(json: JSON) -> [RLMObject] {
        var newEntities : [RLMObject] = []
        let classType = self.self
        for (index: String, model: JSON) in json {
            var dictionary = model.dictionaryObject
            let idAsString = model["id"].stringValue
            dictionary?.updateValue(idAsString, forKey: "id")
        
            // Convert all date strings to NSDates
            let dateFormatter : NSDateFormatter = NSDateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            for (k,v) in dictionary! {
                if let dateString = v as? String {
                    let newV = dateFormatter.dateFromString(dateString)
                    if(newV != nil) {
                        dictionary?.updateValue(newV!, forKey: k)
                    }
                }
            }
            
            newEntities.append( classType.createOrUpdateInDefaultRealmWithObject(dictionary!) )
        }
        for ne in newEntities as! [EfinsModel] {
            ne.dirty = false
        }
        return newEntities
    }
    
    func toJSON() -> JSON {
        var json = JSON([String: AnyObject]())
        let dRealm = RLMRealm.defaultRealm()
        let className = self.description.componentsSeparatedByString(" ")[0]
        //NSLog("toJSON on \(className)")
        let sourceSchema = dRealm.schema.schemaForClassName(className)
        for p in sourceSchema.properties {
            let property: RLMProperty = p as! RLMProperty
            
            if property.type == RLMPropertyType.Array {
                var idArray = [String]()
                let rawArray = self[property.name] as? RLMArray
                if (rawArray != nil) && (rawArray?.count > 0) {
                    for val in rawArray! {
                        let m = val as! EfinsModel
                        idArray.append(m.id)
                        json[property.name] = JSON(idArray)
                    }
                }
            } else if property.type == RLMPropertyType.Object {
                let obj = self[property.name] as? RLMObject
                if obj != nil {
                    json[property.name] = JSON(self[property.name].id)
                }
            } else if property.type == RLMPropertyType.Date {
                let obj = self[property.name] as? NSDate
                if obj != nil {
                    json[property.name] = JSON(obj!.timeIntervalSince1970)
                }
            } else {
                if !(contains(["dirty", "localId"], property.name)) {
                    json[property.name] = JSON(self.valueForKey(property.name)!)
                }
            }
        }
        return json
        
    }
    
    
}
