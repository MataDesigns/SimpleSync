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

public enum SimpleSyncError: Error {
    case empty
    case invalidProperty
}

@objc public protocol SimpleSyncDelegate {
    func entityCreation(_ sync: SimpleSync, json: [String: Any], entity: NSManagedObject)
    func didComplete(_ sync: SimpleSync)
    @objc optional func processJson(_ sync: SimpleSync, json: [String: Any]) -> [[String: Any]]
}

public protocol SimpleSyncThreadDelegate {
    func syncFailed()
}

public class SimpleSync: NSObject {
    
    public struct PagingInfo {
        public var pages: Int    }
    
    private var syncThread: Thread!
    private var dataManager: CoreDataManager
    private lazy var managedObjectContext: NSManagedObjectContext = {
        return self.dataManager.managedObjectContext
    }()
    private var entityName: String
    private var url: String
    private var idProperty: String
    private var createdProperty: String
    private var retried: Int = 0
    
    
    /// The maximum number of failed attempts allowed before sync thread is finished.
    public var maxRetry: Int = 5
    
    /// The delay between each request
    public var requestDelay: UInt32 = 300
    
    public var threadDelegate: SimpleSyncThreadDelegate?
    public var syncDelegate: SimpleSyncDelegate?
    
    public init(manager: CoreDataManager, url: String, entityName: String, withCreatedName idProperty: String = "id", createdProperty: String = "createdOn") {
        self.url = url
        self.dataManager = manager
        self.entityName = entityName
        self.idProperty = idProperty
        self.createdProperty = createdProperty
        super.init()
        self.syncThread = Thread(target: self, selector: #selector(self.syncLoop), object: nil)
    }
    
    
    /// Start the sync thread.
    public func start() {
        self.syncThread.start()
        print("start")
    }
    
    /// Stop the sync thread.
    public func stop() {
        self.syncThread.cancel()
        print("stop")
    }
    
    private func latest() throws -> Date {
        var request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
        
        var sortDescriptor = NSSortDescriptor(key: self.createdProperty, ascending: false)
        request.sortDescriptors?.append(sortDescriptor)
        request.fetchLimit = 1
        
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [self.createdProperty]
        
        do {
            let result = try dataManager.managedObjectContext.fetch(request) as! [[String:Any]]
            guard let first = result.first else {
                throw SimpleSyncError.empty
            }
            guard let latest = first[self.createdProperty] as? Date else {
                throw SimpleSyncError.invalidProperty
            }
            return latest
        } catch {
            throw error
        }
    }
    
    public func processObjects(_ jobjects: [[String: Any]]) {
        do {
            var request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
            request.resultType = .dictionaryResultType
            request.returnsDistinctResults = true
            request.propertiesToFetch = [self.idProperty]
            let result = try dataManager.managedObjectContext.fetch(request) as! [[String:Any]]
            
            let ids = result.map { (object) -> Any in
                return object[self.idProperty] as Any
            }
            
            for var jobject in jobjects {
                let exists = ids.contains(where: { (id) -> Bool in
                    if jobject[self.idProperty] is String {
                        return id as! String == jobject[self.idProperty] as! String
                    } else {
                        return id as! Int == jobject[self.idProperty] as! Int
                    }
                })
                if !exists {
                    let entity = NSEntityDescription.insertNewObject(forEntityName: self.entityName, into: self.managedObjectContext)
                    self.syncDelegate?.entityCreation(self, json: jobject, entity: entity)
                }
            }
        } catch {
            print("invalid key name: \(self.idProperty) for entity named: \(self.entityName)")
        }
        
        do {
            try self.managedObjectContext.save()
        } catch {
            print("failed to save ")
            print(error)
        }
        
        self.syncDelegate?.didComplete(self)
    }
    
    public func sync() {
        Alamofire.request(self.url, method: .get).responseJSON { response in
            switch response.result {
            case .success(let data):
                print("successful")
                if let json = data as? [String: Any] {
                    guard let jobjects = self.syncDelegate?.processJson?(self, json: json) else {
                        print("processJson delegate is needed could not json was not an array.")
                        return
                    }
                    self.processObjects(jobjects)
                    
                } else if let jobjects = data as? [[String: Any]] {
                    self.processObjects(jobjects)
                }
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func syncLoop() {
        while self.retried < self.maxRetry {
            print("running")
            do {
                let latest = try self.latest()
                
                let sem = DispatchSemaphore(value: 0)
                
                Alamofire.request(self.url, method: .get, parameters: ["":latest]).responseJSON { response in
                    switch response.result {
                    case .success:
                        print("successful")
                        self.retried = 0
                    case .failure(let error):
                        print(error)
                        self.retried += 1
                    }
                    sem.signal()
                }
                sem.wait()
                sleep(self.requestDelay)
            } catch  {
                retried += 1
            }
        }
        self.threadDelegate?.syncFailed()
        print("max retries reached")
    }
}
