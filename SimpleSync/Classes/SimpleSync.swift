//
//  SimpleSync.swift
//  Pods
//
//  Created by Nicholas Mata on 1/29/17.
//
//

import UIKit
import CoreData
import Alamofire

class SimpleSync: NSObject {

    var syncThread: Thread!
    var dataManager: CoreDataManager
    var entityName: String
    
    init(manager: CoreDataManager, url: String, entityName: String) {
        self.dataManager = manager
        self.entityName = entityName
        super.init()
        self.syncThread = Thread(target: self, selector: #selector(self.syncLoop), object: nil)
    }
    
    func syncLoop() {
        let customer = NSEntityDescription.insertNewObject(forEntityName: self.entityName, into: dataManager.managedObjectContext)
    }
}
