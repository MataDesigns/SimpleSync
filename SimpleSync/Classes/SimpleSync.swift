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

public class EntitySyncInfo {
    public var idKey: String = "id"
    public var predicate: NSPredicate?
    public var entityName: String
    public var dataManager: CoreDataManager
    
    public lazy var managedObjectContext: NSManagedObjectContext =  {
        return self.dataManager.managedObjectContext
    }()
    
    public var ids: [Any]? {
        let idKey = self.idKey
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.entityName)
        request.predicate = self.predicate
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [idKey]
        guard let result = try? self.dataManager.managedObjectContext.fetch(request) as! [[String:Any]] else {
            return [Any]()
        }
        
        return result.map { (object) -> Any in
            return object[idKey] as Any
        }
    }
    
    public init(dataManager: CoreDataManager, entityName: String) {
        self.dataManager = dataManager
        self.entityName = entityName
    }
}


public protocol EntitySyncDelegate {
    func add(entity: NSManagedObject, with json: [String: Any])
    func update(entity: NSManagedObject, with json: [String: Any])
    func entityOperation(finished operation: EntitySyncOperation)
}

public class EntitySyncOperation: Operation {
    
    private var syncInfo: EntitySyncInfo
    private var jsonObjects: [[String:Any]]
    public var delegate: EntitySyncDelegate?
    
    public init(syncInfo: EntitySyncInfo, jsonObjects: [[String: Any]]) {
        self.jsonObjects = jsonObjects
        self.syncInfo = syncInfo
    }
    
    private func fetchEntity(context: NSManagedObjectContext, withId id: Any) -> NSManagedObject? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: self.syncInfo.entityName)
        if let stringId = id as? String {
            let predicate = NSPredicate(format: "\(self.syncInfo.idKey) == %@", stringId)
            request.predicate = predicate
        } else if let intId = id as? Int {
            let predicate = NSPredicate(format: "\(self.syncInfo.idKey) == %d", intId)
            request.predicate = predicate
        }
        request.fetchLimit = 1
        do {
            let result = try context.fetch(request)
            return (result.first as? NSManagedObject)
        } catch {
            return nil
        }
    }
    
    public override func main() {
        let idKey = self.syncInfo.idKey
        let privateMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateMOC.parent = self.syncInfo.managedObjectContext
        
        privateMOC.performAndWait {
            for jsonObject in self.jsonObjects {
                guard let jsonId = jsonObject[idKey] else {
                    return
                }
                if let entity = self.fetchEntity(context: privateMOC, withId: jsonId)  {
                    self.delegate?.update(entity: entity, with: jsonObject)
                } else {
                    let entity = NSEntityDescription.insertNewObject(forEntityName: self.syncInfo.entityName, into: privateMOC)
                    self.delegate?.add(entity: entity, with: jsonObject)
                }
            }
            do {
                try privateMOC.save()
                self.syncInfo.managedObjectContext.performAndWait {
                    do {
                        try self.syncInfo.managedObjectContext.save()
                    } catch {
                        return
                    }
                }
            } catch {
                return
            }
        }
        self.delegate?.entityOperation(finished: self)
    }
    
}

public protocol NetworkSyncDelegate {
    func networkOperation(_ operation: NetworkSyncOperation, receivedUrl url: String)
    func networkOperation(_ operation: NetworkSyncOperation, receivedJson jsonObjects: [[String: Any]])
    func networkOperation(finished operation: NetworkSyncOperation)
}

public class NetworkSyncOperation: Operation {
    
    private var request: DataRequest
    public var delegate: NetworkSyncDelegate?
    
    public init(request: DataRequest) {
        self.request = request
    }
    
    public convenience init(request: DataRequest, delegate: NetworkSyncDelegate) {
        self.init(request: request)
        self.delegate = delegate
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
                let fullUrl = section[0]
                let url = urlRegex.stringByReplacingMatches(in: fullUrl, range: NSRange(location: 0, length: fullUrl.count), withTemplate: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
                
                
                let nameRegex = try NSRegularExpression(pattern: "rel\\=\\\"(.*)\\\"")
                let fullName = section[1]
                let name = nameRegex.stringByReplacingMatches(in: fullName, range: NSRange(location: 0, length: fullName.count), withTemplate: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
                links[name] = url
            } catch  {
                continue
            }
        }
        
        return links
    }
    
    public override func main() {
        print("Sending request to \(request.request?.url?.absoluteString ?? "Unknown")")
        let sem = DispatchSemaphore(value: 0)
        // 1
        if !self.isCancelled {
            request.responseJSON { response in
                // 2
                if !self.isCancelled {
                    if let remainingHeader = response.response?.allHeaderFields["X-RateLimit-Remaining"] as? String {
                        print("Remaining Requests: \(remainingHeader)")
                        if Int(remainingHeader) == 0 {
                            sem.signal()
                            return
                        }
                    }
                    print("Received Header: \(response.response?.allHeaderFields ?? [AnyHashable:Any]())")
                    if let linkHeader = response.response?.allHeaderFields["Link"] as? String  {
                        let links = self.parseLink(header: linkHeader)
                        if let next = links["next"] {
                            self.delegate?.networkOperation(self, receivedUrl: next)
                        } else {
                            self.delegate?.networkOperation(finished: self)
                        }
                    }else {
                        self.delegate?.networkOperation(finished: self)
                    }
                }
                // 3
                if !self.isCancelled {
                    switch response.result {
                    case .success(let data):
                        // 4
                        if !self.isCancelled {
                            guard let json = data as? [[String: Any]] else {
                                break
                            }
                            
                            self.delegate?.networkOperation(self, receivedJson: json)
                        }
                    case .failure(let error):
                        print(error)
                    }
                }
                sem.signal()
            }
            sem.wait()
        }
    }
}

public protocol SimpleSyncDelegate {
    func simpleSync(_ sync: SimpleSync, fill entity: NSManagedObject, with json: [String: Any])
    func simpleSync(_ sync: SimpleSync, new entity: NSManagedObject, with json: [String: Any])
    func simpleSync(finished sync: SimpleSync)
}

public class SimpleSync: NSObject, NetworkSyncDelegate, EntitySyncDelegate {
    
    
    public var url: String
    public var syncInfo: EntitySyncInfo
    
    public var headers: HTTPHeaders?
    
    public var delegate: SimpleSyncDelegate?
    
    public var networkOperationQueue: OperationQueue
    public var entityOperationQueue: OperationQueue
    
    private var networkOperationCounter = 1
    private var entityOperationCounter = 1
    
    private var networkRequestFinished = false
    
    public init(startUrl: String, info: EntitySyncInfo) {
        self.url = startUrl
        self.syncInfo = info
        
        self.networkOperationQueue = OperationQueue()
        self.networkOperationQueue.name = "SimpleSyncNetworkQueue"
        
        self.entityOperationQueue = OperationQueue()
        self.entityOperationQueue.name = "SimpleSyncEntityQueue"
    }
    
    public func start() {
        if networkRequestFinished {
            networkRequestFinished = false
        }
        networkOperationCounter = 1
        entityOperationCounter = 1
        self.networkOperationQueue.cancelAllOperations()
        addToNetworkQueue(url: url)
    }
    
    public func stop() {
        self.networkOperationQueue.cancelAllOperations()
    }
    
    private func addToNetworkQueue(url: String) {
        let request = Alamofire.request(url, method: .get, headers: self.headers)
        let operation = NetworkSyncOperation(request: request)
        operation.name = String(self.networkOperationCounter)
        operation.delegate = self
        self.networkOperationQueue.addOperation(operation)
        self.networkOperationCounter += 1
    }
    
    private func addToEntityQueue(jsonObjects: [[String : Any]]) {
        let operation = EntitySyncOperation(syncInfo: self.syncInfo, jsonObjects: jsonObjects)
        operation.name = String(self.entityOperationCounter)
        operation.delegate = self
        self.entityOperationQueue.addOperation(operation)
        self.entityOperationCounter += 1
    }
    
    // EntitySyncDelegate
    public func add(entity: NSManagedObject, with json: [String : Any]) {
        // print("Adding \(json[self.syncInfo.idKey] ?? "")")
        self.delegate?.simpleSync(self, new: entity, with: json)
    }
    
    public func update(entity: NSManagedObject, with json: [String : Any]) {
        // print("Updating \(json[self.syncInfo.idKey] ?? "")")
        self.delegate?.simpleSync(self, fill: entity, with: json)
    }
    
    // NetworkSyncDelegate
    public func networkOperation(_ operation: NetworkSyncOperation, receivedUrl url: String) {
        addToNetworkQueue(url: url)
    }
    
    public func networkOperation(_ operation: NetworkSyncOperation, receivedJson json: [[String:Any]]) {
        // print("Received objects for \(operation.name ?? "")")
        addToEntityQueue(jsonObjects: json)
    }
    
    public func networkOperation(finished operation: NetworkSyncOperation) {
        // print("Finished on operation \(operation.name ?? "")")
        networkRequestFinished = true
    }
    
    public func entityOperation(finished operation: EntitySyncOperation) {
        if entityOperationCounter == networkOperationCounter && networkRequestFinished {
            self.delegate?.simpleSync(finished: self)
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
