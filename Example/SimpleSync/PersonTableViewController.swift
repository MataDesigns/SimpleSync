//
//  PersonTableViewController.swift
//  SimpleSync
//
//  Created by Nicholas Mata on 2/1/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import CoreData
import SimpleSync

class PersonCell: UITableViewCell {
    @IBOutlet weak var firstNameLabel: UILabel!
    @IBOutlet weak var lastNameLabel: UILabel!
}

class PersonTableViewController: UITableViewController {
    
    var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>!
    
    func initializeFetchedResultsController() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Person")
        let initialSort = NSSortDescriptor(key: "lastInitial", ascending: true)
        let firstNameSort = NSSortDescriptor(key: "firstName", ascending: true)
        request.sortDescriptors = [initialSort, firstNameSort]
        
        let moc = CoreDataManager.shared.managedObjectContext
        fetchedResultsController = NSFetchedResultsController(fetchRequest: request, managedObjectContext: moc, sectionNameKeyPath: "lastInitial", cacheName: nil)
        // For smaller data sets this is better.
        //fetchedResultsController.delegate = self
        
        do {
            try fetchedResultsController.performFetch()
        } catch {
            fatalError("Failed to initialize FetchedResultsController: \(error)")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        initializeFetchedResultsController()
        let dataManager = CoreDataManager.shared
        
        let sync = SimpleSync(manager: dataManager, url: "http://192.168.0.2/api/customers", entityName: "Person")
        sync.headers = ["Authorization": "Bearer kyOhwUIid1AFbomxpFR16ojznRmpXu-7eUxH2uj_TIBOeD8UUxMEh3PXPP5vYTZcS3zoKkh2_thFqz8cy5yOFkUaHitaSEhpCEjQgl81xIRajOO-wQgS2eS26oGr8subcpjLlQWqSkfO82FeBXRAgkTyhlzhmYPydFcQb3HdyfEDvz-Aoc8yK4s8OQZtXNb6o0CEyi9KQqfVBUgT3g0AfblNJpAfzAZF8_9uD8wRtDBSqD9WOcnO3V7SZFo5aDkTA7R-uCePQ4JY_F1vr8fxmOugLGU5yu0aAi10_-VWBy0hsrWnfi44aCb8vBCcX8EH4jaztNIidzUqmvA3A_4OoFna_NK_az7P48MBsH_xgxrEF8g_SJR35zeEazwnBkknWwvB7OasgvAiCob6hSVr9WdBB40LujV8u4EnTH0im9qrDAzphH-sBP52eILD2nUhvUv39VhzZcdtmfI_uac87ySLwt5sHnkYTAvTMzeM9Z8NopPrUZheqtTaHizfkGJ7R8M2ih0pgw09g-0i8q2AHA"]
        sync.size = 1000
        sync.delegate = self
        sync.sync()
    }
}

extension PersonTableViewController: SimpleSyncDelegate {
    func syncEntity(_ sync: SimpleSync, fillEntity entity: NSManagedObject, with json: [String : Any]) {
        guard let entity = entity as? Person else {
            return
        }
        let id = json["id"] as! Int64
        SimpleSync.updateIfChanged(entity, key: "id", value: id)
        let firstName = json["firstName"] as? String
        SimpleSync.updateIfChanged(entity, key: "firstName", value: firstName)
        let lastName = json["lastName"] as? String
        SimpleSync.updateIfChanged(entity, key: "lastName", value: lastName)
        
        if let lastName = lastName {
            let lastInitial: String? = String(lastName.characters.prefix(1)).capitalized
            SimpleSync.updateIfChanged(entity, key: "lastInitial", value: lastInitial)
        } else {
            entity.lastInitial = ""
        }
    }
    
    func didComplete(_ sync: SimpleSync, hadChanges: Bool) {
        if hadChanges {
            do {
                try fetchedResultsController.performFetch()
            } catch {
                fatalError("Failed to initialize FetchedResultsController: \(error)")
            }
            tableView.reloadData()
        }
    }
}

extension PersonTableViewController {
    
    func configureCell(_ cell: UITableViewCell, indexPath: IndexPath) {
        guard let selectedObject = fetchedResultsController.object(at: indexPath) as? Person else { fatalError("Unexpected Object in FetchedResultsController")
        }
        guard let cell = cell as? PersonCell else {
            fatalError("Invalid cell class")
        }
        cell.firstNameLabel.text = selectedObject.firstName
        cell.lastNameLabel.text = selectedObject.lastName
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return fetchedResultsController.sections?[section].indexTitle
    }
    
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return fetchedResultsController.sectionIndexTitles
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PersonCell", for: indexPath)
        // Set up the cell
        configureCell(cell, indexPath: indexPath)
        return cell
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections?.count ?? 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController.sections else {
            fatalError("No sections in fetchedResultsController")
        }
        let sectionInfo = sections[section]
        return sectionInfo.numberOfObjects
    }
}

// Set delegate in viewDidLoad to use these methods.
// Only recommended for smaller data sets.
extension PersonTableViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            configureCell(tableView.cellForRow(at: indexPath!)!, indexPath: indexPath!)
        case .move:
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(NSIndexSet(index: sectionIndex) as IndexSet, with: .fade)
        case .delete:
            tableView.deleteSections(NSIndexSet(index: sectionIndex) as IndexSet, with: .fade)
        case .move:
            break
        case .update:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}
