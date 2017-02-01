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

public protocol SimpleSyncDelegate {
    func processJson(_ sync: SimpleSync, json: [String: Any]) -> [[String: Any]]
    func syncEntity(_ sync: SimpleSync, fillEntity entity: NSManagedObject, with json: [String: Any])
    
    func didComplete(_ sync: SimpleSync, hadChanges: Bool)
}

public class SimpleSync: NSObject {
    
    /// The number of pages.
    public var pages: UInt = 1

    
    public var idKey: String
    public var pageKey: String
    public var pageTotalKey: String
    
    public var delegate: SimpleSyncDelegate?
    
    private var syncThread: Thread!
    private var dataManager: CoreDataManager
    private lazy var managedObjectContext: NSManagedObjectContext = {
        return self.dataManager.managedObjectContext
    }()
    private var entityName: String
    private var url: String
    
    public init(manager: CoreDataManager, url: String, entityName: String,
                idKey: String = "id", pageKey: String = "page", pageTotalKey: String = "total_pages") {
        self.url = url
        self.dataManager = manager
        self.entityName = entityName
        
        self.idKey = idKey
        self.pageKey = pageKey
        self.pageTotalKey = pageTotalKey
        
        super.init()
        self.syncThread = Thread(target: self, selector: #selector(self.syncLoop), object: nil)
    }
    
    
    /// Start the sync.
    public func sync() {
        self.syncThread.start()
        print("start")
    }
    
    private func fetchEntity(withId id: Any) throws -> NSManagedObject {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
        if let stringId = id as? String {
            let predicate = NSPredicate(format: "\(self.idKey) == %@", stringId)
            request.predicate = predicate
        } else if let intId = id as? Int {
            let predicate = NSPredicate(format: "\(self.idKey) == %d", intId)
            request.predicate = predicate
        }
        request.fetchLimit = 1
        let result = try dataManager.managedObjectContext.fetch(request)
        
        return (result.first as! NSManagedObject)
    }
    
    private func processObjects(_ jobjects: [[String: Any]], ids: [Any]) {
        
        for var jobject in jobjects {
            let exists = ids.contains(where: { (id) -> Bool in
                if jobject[self.idKey] is String {
                    return id as! String == jobject[self.idKey] as! String
                } else {
                    return id as! Int == jobject[self.idKey] as! Int
                }
            })
            if !exists {
                let entity = NSEntityDescription.insertNewObject(forEntityName: self.entityName, into: self.managedObjectContext)
                self.delegate?.syncEntity(self, fillEntity: entity, with: jobject)
            } else {
                do {
                    let entity = try fetchEntity(withId: jobject[self.idKey] is String ? jobject[self.idKey] as! String : jobject[self.idKey] as! Int )
                    self.delegate?.syncEntity(self, fillEntity: entity, with: jobject)
                } catch  {
                    print(error)
                }
                
            }
        }
        
    }
    
    public func syncLoop() {
        
        do {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
            request.resultType = .dictionaryResultType
            request.returnsDistinctResults = true
            request.propertiesToFetch = [self.idKey]
            let result = try dataManager.managedObjectContext.fetch(request) as! [[String:Any]]
            
            let existingIds = result.map { (object) -> Any in
                return object[self.idKey] as Any
            }
            
            var serverIds = [Any]()
            
            let sem = DispatchSemaphore(value: 0)
            
            Alamofire.request("\(url)?\(pageKey)=\(1)", method: .get).responseJSON { response in
                switch response.result {
                case .success(let data):
                    print("successful")
                    if let json = data as? [String: Any] {
                        guard let pageTotal = json[self.pageTotalKey] as? UInt else {
                            return
                        }
                        self.pages = pageTotal
                        guard let jobjects = self.delegate?.processJson(self, json: json) else {
                            print("processJson delegate is needed could not json was not an array.")
                            return
                        }
                        
                        let callIds = jobjects.map({ (jObject) -> Any in
                            return jObject[self.idKey]
                        })
                        
                        serverIds.append(contentsOf: callIds)
                        
                        
                        self.processObjects(jobjects, ids: existingIds)
                    }
                case .failure(let error):
                    print(error)
                }
                sem.signal()
            }
            
            sem.wait()
            
            
            for page in 2...self.pages {
                print("fetching page \(page)")
                
                let sem = DispatchSemaphore(value: 0)
                
                Alamofire.request("\(url)?\(pageKey)=\(page)", method: .get).responseJSON { response in
                    switch response.result {
                    case .success(let data):
                        print("successful")
                        if let json = data as? [String: Any] {
                            guard let pageTotal = json[self.pageTotalKey] as? UInt else {
                                return
                            }
                            self.pages = pageTotal
                            guard let jobjects = self.delegate?.processJson(self, json: json) else {
                                print("processJson delegate is needed could not json was not an array.")
                                return
                            }
                            
                            let callIds = jobjects.map({ (jObject) -> Any in
                                return jObject[self.idKey]
                            })
                            
                            serverIds.append(contentsOf: callIds)
                            
                            
                            self.processObjects(jobjects, ids: existingIds)
                        }
                    case .failure(let error):
                        print(error)
                    }
                    sem.signal()
                }
                
                sem.wait()
                print("total pages: \(self.pages)")
            }
            
            if existingIds.first is Int {
                let removed = Array(Set(existingIds as! [Int]).subtracting(serverIds as! [Int]))
                print("removed \(removed)")
            }
            
            let hasChanges = self.managedObjectContext.hasChanges
            
            do {
                try self.managedObjectContext.save()
            } catch {
                print("failed to save ")
                print(error)
            }
            
            self.delegate?.didComplete(self, hadChanges: hasChanges)
            
            
        } catch {
            print("invalid key name: \(self.idKey) for entity named: \(self.entityName)")
        }
        
    }
}

public extension SimpleSync {
    
    public class func updateIfChanged<K: Comparable>(_ entity: NSManagedObject, key: String, value: K) {
        if entity.value(forKey: key) as! K != value {
            entity.setValue(value, forKey: key)
        }
    }
    
    public class func updateIfChanged<K: Comparable>(_ entity: NSManagedObject, key: String, value: K?) {
        if entity.value(forKey: key) as? K != value {
            entity.setValue(value, forKey: key)
        }
    }
    
}
