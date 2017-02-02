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
    // func processJson(_ sync: SimpleSync, json: [String: Any]) -> [[String: Any]]
    func syncEntity(_ sync: SimpleSync, fillEntity entity: NSManagedObject, with json: [String: Any])
    
    func didComplete(_ sync: SimpleSync, hadChanges: Bool)
}

public class SimpleSync: NSObject {
    
    
    public var entityName: String
    public var url: String
    public var size: Int?
    public var headers: HTTPHeaders?
    public var predicate: NSPredicate?
    
    public var idKey: String = "id"
    
    public var delegate: SimpleSyncDelegate?
    
    private let responseQueue = DispatchQueue(label: "com.simplesync.responsequeue", qos: .utility, attributes: [.concurrent])
    private var syncThread: Thread!
    private var dataManager: CoreDataManager
    private lazy var managedObjectContext: NSManagedObjectContext = {
        return self.dataManager.managedObjectContext
    }()
    
    public init(manager: CoreDataManager, url: String, entityName: String) {
        self.url = url
        self.dataManager = manager
        self.entityName = entityName
        
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
    
    func parseLink(header: String) -> [String: String] {
        
        let components = header.components(separatedBy: ",")
        var links = [String: String]()
        
        for component in components {
            var section = component.components(separatedBy: ";")
            if section.count != 2 {
                continue
            }
            do {
                let urlRegex = try NSRegularExpression(pattern: "\\<(.*)\\>")
                var fullUrl = section[0]
                var url = urlRegex.stringByReplacingMatches(in: fullUrl, range: NSRange(location: 0, length: fullUrl.characters.count), withTemplate: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
                
                
                let nameRegex = try NSRegularExpression(pattern: "rel\\=\\\"(.*)\\\"")
                var fullName = section[1]
                var name = nameRegex.stringByReplacingMatches(in: fullName, range: NSRange(location: 0, length: fullName.characters.count), withTemplate: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
                links[name] = url
            } catch  {
                continue
            }
        }
        
        return links
    }
    
    public func syncLoop() {
        
        do {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
            request.predicate = self.predicate
            request.resultType = .dictionaryResultType
            request.returnsDistinctResults = true
            request.propertiesToFetch = [self.idKey]
            let result = try dataManager.managedObjectContext.fetch(request) as! [[String:Any]]
            
            let existingIds = result.map { (object) -> Any in
                return object[self.idKey] as Any
            }

            var serverIds = [Any]()
            
            var url: String? = self.url
            if let size = self.size {
                url?.append("?size=\(size)")
            }
            
            var count = 0
            
            while url != nil {
                let sem = DispatchSemaphore(value: 0)
                
                guard let requestUrl = url else {
                    break;
                }
                
                let request = Alamofire.request(requestUrl, method: .get, headers: self.headers)
                
                request.responseJSON(queue: self.responseQueue) { response in
                    switch response.result {
                    case .success(let data):
                        
                        guard let json = data as? [[String: Any]] else {
                            break
                        }
                        
                        let callIds = json.map({ (jObject) -> Any in
                            return jObject[self.idKey]
                        })
                        
                        serverIds.append(contentsOf: callIds)
                        self.processObjects(json, ids: existingIds)
                        
                        guard let response = response.response else {
                            break;
                        }
                        guard let linkHeader = response.allHeaderFields["Link"] as? String else {
                            break;
                        }
                        let links = self.parseLink(header: linkHeader)
                        if let next = links["next"] {
                            url = next
                        }
                    case .failure(let error):
                        print(error)
                    }
                    sem.signal()
                }
                
                url = nil
                sem.wait()
                print("next url: \(url)")
                count += 1
            }
            
            if existingIds.first is Int {
                let server = serverIds as! [Int]
                let coreData = existingIds as! [Int]
                let removed = Array(Set(coreData).subtracting(server))
                print("removed \(removed)")
            }
            
            let hasChanges = self.managedObjectContext.hasChanges
            
            do {
                try self.managedObjectContext.save()
            } catch {
                print("failed to save ")
                print(error)
            }
            
            DispatchQueue.main.async {
                self.delegate?.didComplete(self, hadChanges: hasChanges)
            }
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
