//
//  RelationTableViewCell.swift
//  eFins-iOS
//
//  Created by CHAD BURT on 3/31/15.
//  Copyright (c) 2015 McClintock Lab. All rights reserved.
//

import UIKit
import Realm

class RelationTableViewCell: UITableViewCell {
    
    var secondaryProperty: RLMProperty?
    @IBInspectable var modelLabelProperty: String = "name"
    @IBInspectable var modelFormClass: String?
    var allowEditing = true
    
    var oneToMany:Bool {
        get {
            println(property)
            return property?.type == RLMPropertyType.Array
//            if let val: AnyObject? = propertyValue {
//                return val is RLMArray
//            } else {
//                return false
//            }
        }
    }
    
    var propertyValue:AnyObject? {
        get {
            if let prop = property {
                return model?.valueForKey(prop.name)
            } else {
                return nil
            }
        }
    }
    
    var hasValue:Bool {
        get {
            let value: AnyObject? = propertyValue
            if value != nil {
                if self.oneToMany {
                    return (value as! RLMArray).count > 0
                } else {
                    return value != nil
                }
            }
            return false
        }
    }
    
    var _model:RLMObject?
    
    var model:RLMObject? {
        set(object) {
            self._model = object
            updateValues()
        }
        get {
            return self._model
        }
    }
    
    var _property:RLMProperty?
    
    var property:RLMProperty? {
        set(object) {
            self._property = object
            updateValues()
        }
        get {
            return self._property
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    func updateValues() {
        println("updateValues")
        if model != nil {
            if oneToMany {
                println("One to MAny")
                let array:RLMArray = propertyValue as! RLMArray
                self.detailTextLabel?.text = "\(array.count)"
                self.updateRecentValuesCounts()
                if array.count < 1 && !allowEditing {
                    println("Setting accessory type")
                    self.accessoryType = UITableViewCellAccessoryType.None
                } else {
                    self.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
                }
            } else {
                if let object: AnyObject = propertyValue {
                    self.detailTextLabel?.text = "\(object.valueForKey(modelLabelProperty))"
                } else {
                    self.detailTextLabel?.text = "None"
                }
                if !allowEditing {
                    self.accessoryType = UITableViewCellAccessoryType.None
                }
            }
        } else {
            self.detailTextLabel?.text = " "
        }
    }
    
    func updateRecentValuesCounts() {
        if model != nil {
            if oneToMany {
                let array:RLMArray = propertyValue as! RLMArray
                var i = 0
                while i < Int(array.count) {
                    let item = array.objectAtIndex(UInt(i)) as! RLMObject?
                    RecentValues.increment(item!, model: self.model!, property: self.property!)
                    i++
                }
            } else {
                if let item = propertyValue as? RLMObject {
                    RecentValues.increment(item, model: self.model!, property: self.property!)
                }
            }
        }
    }
    
    override func setSelected(selected: Bool, animated: Bool) {
        if selected {
            if allowEditing || hasValue {
                let storyboard = UIStoryboard(name: "OneToMany", bundle: nil)
                let destination = storyboard.instantiateInitialViewController() as! OneToManyTableViewController
                let table:UITableView = self.superview?.superview as! UITableView
                let controller = table.dataSource as! UITableViewController
                destination.title = self.textLabel?.text
                destination.model = model
                destination.modelFormClass = modelFormClass
                destination.modelLabelProperty = modelLabelProperty
                destination.property = property
                destination.secondaryProperty = secondaryProperty
                destination.entryFieldName = self.textLabel?.text
                destination.cell = self
                destination.allowEditing = allowEditing
                controller.navigationController?.pushViewController(destination, animated: true)
            }
        }
        super.setSelected(selected, animated: animated)
    }

}
