//
//  PersonTableViewController.swift
//  SimpleSync
//
//  Created by Nicholas Mata on 1/31/17.
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
        let lastNameSort = NSSortDescriptor(key: "lastName", ascending: true)
        request.sortDescriptors = [lastNameSort]
        
        let moc = CoreDataManager.shared.managedObjectContext
        fetchedResultsController = NSFetchedResultsController(fetchRequest: request, managedObjectContext: moc, sectionNameKeyPath: "lastName", cacheName: nil)
        fetchedResultsController.delegate = self
        
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
        
        let sync = SimpleSync(manager: dataManager, url: "https://reqres.in/api/users", entityName: "Person")
        sync.delegate = self
        sync.sync()
    }
}

extension PersonTableViewController: SimpleSyncDelegate {
    func processJson(_ sync: SimpleSync, json: [String : Any]) -> [[String : Any]] {
        return json["data"] as! [[String: Any]]
    }
    
    func syncEntity(_ sync: SimpleSync, fillEntity entity: NSManagedObject, with json: [String : Any]) {
        guard let entity = entity as? Person else {
            return
        }
        let id = json["id"] as! Int64
        SimpleSync.updateIfChanged(entity, key: "id", value: id)
        let firstName = json["first_name"] as? String
        SimpleSync.updateIfChanged(entity, key: "firstName", value: firstName)
        let lastName = json["last_name"] as? String
        SimpleSync.updateIfChanged(entity, key: "lastName", value: lastName)
    }
    
    func didComplete(_ sync: SimpleSync, hadChanges: Bool) {
        if hadChanges {
            //tableView.reloadData()
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
        // Populate cell from the NSManagedObject instance
        // print("Object for configuration: \(selectedObject)")
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let name = fetchedResultsController.sections?[section].name {
            let start = name.index(name.startIndex, offsetBy: 1)
            return name.substring(to: start).capitalized
        }
        return nil
    }
    
    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        if let sections = fetchedResultsController.sections {
            return sections.map({ (section) -> String in
                let name = section.name
                let start = name.index(name.startIndex, offsetBy: 1)
                return name.substring(to: start).capitalized
            })
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "personCell", for: indexPath)
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
