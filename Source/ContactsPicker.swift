//
//  ContactsPicker.swift
//  JFContactsPicker
//

import UIKit
import Contacts

public protocol ContactsPickerDelegate: class {
    func contactPicker(_: ContactsPicker, didContactFetchFailed error: NSError)
    func contactPicker(_: ContactsPicker, didCancel error: NSError)
    func contactPicker(_: ContactsPicker, didSelectContact contact: Contact)
    func contactPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact])
}

public extension ContactsPickerDelegate {
    func contactPicker(_: ContactsPicker, didContactFetchFailed error: NSError) { }
    func contactPicker(_: ContactsPicker, didCancel error: NSError) { }
    func contactPicker(_: ContactsPicker, didSelectContact contact: Contact) { }
    func contactPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) { }
}

typealias ContactsHandler = (_ contacts : [CNContact] , _ error : NSError?) -> Void

public enum SubtitleCellValue{
    case phoneNumber
    case email
    case birthday
    case organization
}

open class ContactsPicker: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {
    
    // MARK: - Properties
    
    public private(set) lazy var contactsStore: CNContactStore = { return CNContactStore() }()
    
    /// Contacts ordered in dictionary alphabetically using `sortOrder`.
    private var contactsHolder = ContactsHolder()

    /// Contacts ordered in dictionary alphabetically using `sortOrder` that are using the app.
    private var contactsHolderUsingApp = ContactsHolder()

    public private(set) var selectedContacts = [Contact]()
    
    /// The `delegate` for the picker.
    open weak var contactDelegate: ContactsPickerDelegate?
    
    /// If `true`, the picker will allow multiple contacts to be selected.
    /// Defaults to `false` for single contact selection.
    public let multiSelectEnabled: Bool
    
    /// Indicates if the index bar should be shown. Defaults to `true`.
    public var shouldShowIndexBar: Bool
    
    /// The contact value type to display in the cells' subtitle labels.
    public let subtitleCellValue: SubtitleCellValue
    
    /// The order that the contacts should be sorted.
    public var sortOrder: CNContactSortOrder = CNContactSortOrder.userDefault {
        didSet {
            if viewIfLoaded != nil {
                self.reloadContacts()
            }
        }
    }
    
    // Filter to indicate if this contact already using the app
    public var contactUsingAppFilter:((CNContact) -> Bool)?
    
    //Enables custom filtering of contacts.
    public var shouldIncludeContact: ((CNContact) -> Bool)? {
        didSet {
            if viewIfLoaded != nil {
                self.reloadContacts()
            }
        }
    }
    
    public lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar(frame: CGRect.zero)
        searchBar.placeholder = "Search"
        searchBar.delegate = self
        return searchBar
    }()
    
    public private(set) lazy var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect.zero, style: .plain)
        tableView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()
    
    // MARK: - Initializers
    
    /// The designated initializer.
    ///
    /// - Parameters:
    ///   - delegate:           The delegate for the picker. Defaults to `nil`.
    ///   - multiSelection:     `true` for multiple selection, `false` for single selection. Defaults to `false`.
    ///   - showIndexBar:       `true` to show the index bar, `false` to hide the index bar. Defaults to `true`.
    ///   - subtitleCellType:   The value type to display in the subtitle label on the contact cells.
    ///                         Defaults to `.phoneNumber`.
    public init(delegate: ContactsPickerDelegate? = nil,
                multiSelection: Bool = false,
                showIndexBar: Bool = true,
                subtitleCellType: SubtitleCellValue = .phoneNumber,
                contactUsingAppFilter:((CNContact) -> Bool)? = nil) {
        self.multiSelectEnabled = multiSelection
        self.subtitleCellValue = subtitleCellType
        self.shouldShowIndexBar = showIndexBar
        self.contactUsingAppFilter = contactUsingAppFilter
        
        super.init(nibName: nil, bundle: nil)
        
        contactDelegate = delegate
    }
    
    required public init?(coder aDecoder: NSCoder) {
        self.multiSelectEnabled = false
        self.subtitleCellValue = .phoneNumber
        self.shouldShowIndexBar = true
        
        super.init(coder: aDecoder)
    }
    
    // MARK: - Lifecycle Methods
    
    open override func loadView() {
        self.view = tableView
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        self.title = GlobalConstants.Strings.contactsTitle
        
        registerContactCell()
        initializeBarButtons()
        setUpSearchBar()
        reloadContacts()
    }
    
    func setUpSearchBar() {
        searchBar.sizeToFit()
        self.tableView.tableHeaderView = searchBar
    }
    
    func initializeBarButtons() {
        let cancelButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.cancel, target: self, action: #selector(onTouchCancelButton))
        self.navigationItem.leftBarButtonItem = cancelButton
        
        if multiSelectEnabled {
            let doneButton = UIBarButtonItem(title: "Done (\(selectedContacts.count))", style: UIBarButtonItemStyle.done, target: self, action: #selector(onTouchDoneButton))
            
            doneButton.isEnabled = false
            
            self.navigationItem.rightBarButtonItem = doneButton
            
        }
    }
    
    func setDoneButtonTitle() {
        
        self.navigationItem.rightBarButtonItem?.isEnabled = selectedContacts.count > 0
        
        UIView.performWithoutAnimation { [unowned self] in
            
            self.navigationItem.rightBarButtonItem?.title = "Done (\(selectedContacts.count))"

        }
        
    }
    
    private func registerContactCell() {
        let podBundle = Bundle(for: self.classForCoder)
        if let bundleURL = podBundle.url(forResource: GlobalConstants.Strings.bundleIdentifier, withExtension: "bundle") {
            
            if let bundle = Bundle(url: bundleURL) {
                
                let cellNib = UINib(nibName: GlobalConstants.Strings.cellNibIdentifier, bundle: bundle)
                tableView.register(cellNib, forCellReuseIdentifier: "Cell")
            }
            else {
                assertionFailure("Could not load bundle")
            }
            
        } else {
            let cellNib = UINib(nibName: GlobalConstants.Strings.cellNibIdentifier, bundle: podBundle)
            tableView.register(cellNib, forCellReuseIdentifier: "Cell")
        }
    }
    
    // MARK: - Contact Operations
    
    open func reloadContacts() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.getContacts { [weak self] (contacts, error) in
                if (error == nil) {
                    DispatchQueue.main.async { [weak self] in
                        self?.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    private func getContacts(_ completion:  @escaping ContactsHandler) {
        // TODO: Set up error domain
        let error = NSError(domain: "EPContactPickerErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Contacts Access"])
        
        switch CNContactStore.authorizationStatus(for: CNEntityType.contacts) {
        case CNAuthorizationStatus.denied, CNAuthorizationStatus.restricted:
            //User has denied the current app to access the contacts.
            
            let productName = Bundle.main.infoDictionary!["CFBundleDisplayName"]!
            
            let alert = UIAlertController(title: "Unable to access contacts", message: "\(productName) does not have access to contacts. Kindly enable it in privacy settings ", preferredStyle: UIAlertControllerStyle.alert)
            let okAction = UIAlertAction(title: "Ok", style: UIAlertActionStyle.default, handler: {  action in
                self.contactDelegate?.contactPicker(self, didContactFetchFailed: error)
                completion([], error)
                self.dismiss(animated: true, completion: nil)
            })
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
            
        case CNAuthorizationStatus.notDetermined:
            //This case means the user is prompted for the first time for allowing contacts
            contactsStore.requestAccess(for: CNEntityType.contacts, completionHandler: { (granted, error) -> Void in
                //At this point an alert is provided to the user to provide access to contacts. This will get invoked if a user responds to the alert
                if  (!granted ){
                    DispatchQueue.main.async(execute: { () -> Void in
                        completion([], error! as NSError?)
                    })
                }
                else{
                    self.getContacts(completion)
                }
            })
            
        case  CNAuthorizationStatus.authorized:
            //Authorization granted by user for this app.
            var contactsArray = [CNContact]()
            var contactsUsingAppArray = [CNContact]()

            var orderedContacts = [String : [CNContact]]()
            var orderedContactsUsingApp = [String : [CNContact]]()

            let contactFetchRequest = CNContactFetchRequest(keysToFetch: allowedContactKeys())
            
            do {
                
                try contactsStore.enumerateContacts(with: contactFetchRequest, usingBlock: { [weak self] (contact, stop) -> Void in
                    
                    //Adds the `contact` to the `contactsArray` if the closure returns true.
                    //If the closure doesn't exist, then the contact is added.
                    if let shouldIncludeContactClosure = self?.shouldIncludeContact, !shouldIncludeContactClosure(contact) {
                        return
                    }
                    
                    var isContactUsingApp = false
                    
                    if let contactUsingAppFilter = self?.contactUsingAppFilter {
                        isContactUsingApp = contactUsingAppFilter(contact)
                    }
                    
                    if isContactUsingApp {
                        contactsUsingAppArray.append(contact)
                    }
                    else {
                        contactsArray.append(contact)

                    }
                    
                    //Ordering contacts based on alphabets in firstname
                    var key: String = "#"
                    
                    //If ordering has to be happening via family name change it here.
                    if let firstLetter = self?.firstLetter(for: contact) {
                        key = firstLetter.uppercased()
                    }
                    
                    if isContactUsingApp {
                        
                        var contactsForKey = orderedContactsUsingApp[key] ?? [CNContact]()
                        contactsForKey.append(contact)
                        orderedContactsUsingApp[key] = contactsForKey
                        
                    }
                    else {
                        
                        var contactsForKey = orderedContacts[key] ?? [CNContact]()
                        contactsForKey.append(contact)
                        orderedContacts[key] = contactsForKey
                        
                    }
                    
                })
                
                self.contactsHolder.orderedContacts = orderedContacts
                self.contactsHolderUsingApp.orderedContacts = orderedContactsUsingApp

                self.contactsHolder.sortedContacts = contactsArray
                self.contactsHolderUsingApp.sortedContacts = contactsUsingAppArray

                self.contactsHolder.sortedContactKeys = Array(self.contactsHolder.orderedContacts.keys).sorted(by: <)
                if self.contactsHolder.sortedContactKeys.first == "#" {
                    self.contactsHolder.sortedContactKeys.removeFirst()
                    self.contactsHolder.sortedContactKeys.append("#")
                }
                
                self.contactsHolderUsingApp.sortedContactKeys = Array(self.contactsHolderUsingApp.orderedContacts.keys).sorted(by: <)
                if self.contactsHolderUsingApp.sortedContactKeys.first == "#" {
                    self.contactsHolderUsingApp.sortedContactKeys.removeFirst()
                    self.contactsHolderUsingApp.sortedContactKeys.append("#")
                }
                
                completion(contactsArray, nil)
                
            } catch let error as NSError {
                /// Catching exception as enumerateContactsWithFetchRequest can throw errors
                print(error.localizedDescription)
            }
            
        }
    }
    
    private func firstLetter(for contact: CNContact) -> String? {
        var firstLetter: String? = nil
        
        switch sortOrder {
            
        case .userDefault where CNContactsUserDefaults.shared().sortOrder == .familyName:
            fallthrough
        case .familyName:
            firstLetter = contact.familyName[0..<1]
            
        case .userDefault where CNContactsUserDefaults.shared().sortOrder == .givenName:
            fallthrough
        case .givenName:
            fallthrough
        default:
            firstLetter = contact.givenName[0..<1]
        }
        
        guard let letter = firstLetter, letter.containsAlphabets() else { return nil }
        return letter
    }
    
    func allowedContactKeys() -> [CNKeyDescriptor]{
        //We have to provide only the keys which we have to access. We should avoid unnecessary keys when fetching the contact. Reducing the keys means faster the access.
        return [CNContactNamePrefixKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactImageDataKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
                CNContactImageDataAvailableKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
    }
    
    // MARK: - Table View DataSource
    
    open func numberOfSections(in tableView: UITableView) -> Int {
        
        if self.contactUsingAppFilter == nil {
            
            if let searchText = searchBar.text, !searchText.isEmpty { return 1 }
            return contactsHolder.sortedContactKeys.count
            
        }
        else{
            return 2
        }
        
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if self.contactUsingAppFilter == nil {
            
            if let searchText = searchBar.text, !searchText.isEmpty { return contactsHolder.filteredContacts.count }
            if let contactsForSection = contactsHolder.orderedContacts[contactsHolder.sortedContactKeys[section]] {
                return contactsForSection.count
            }
            
        }
        else {
            
            if let searchText = searchBar.text, !searchText.isEmpty {
                return section == 0 ? contactsHolderUsingApp.filteredContacts.count : contactsHolder.filteredContacts.count
            }

            return section == 0 ? contactsHolderUsingApp.sortedContacts.count : contactsHolder.sortedContacts.count

        }
        
        
        return 0
    }
    
    // MARK: - Table View Delegates
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! ContactCell
        cell.accessoryType = UITableViewCellAccessoryType.none
        //Convert CNContact to Contact
        let contact: Contact
        
        if let searchText = searchBar.text, !searchText.isEmpty {
            
            if self.contactUsingAppFilter == nil || indexPath.section == 1 {
                contact = Contact(contact: contactsHolder.filteredContacts[(indexPath as NSIndexPath).row])
            }
            else {
                contact = Contact(contact: contactsHolderUsingApp.filteredContacts[(indexPath as NSIndexPath).row])
            }
            
        } else {
            
            if self.contactUsingAppFilter == nil {
                
                guard let contactsForSection = contactsHolder.orderedContacts[contactsHolder.sortedContactKeys[(indexPath as NSIndexPath).section]] else {
                    assertionFailure()
                    return UITableViewCell()
                }
                
                contact = Contact(contact: contactsForSection[(indexPath as NSIndexPath).row])

            }
            else if indexPath.section == 0 {
                
                contact = Contact(contact: self.contactsHolderUsingApp.sortedContacts[(indexPath as NSIndexPath).row])
                
            }
            else {
                
                contact = Contact(contact: self.contactsHolder.sortedContacts[(indexPath as NSIndexPath).row])

            }
            
        }
        
        if multiSelectEnabled  && selectedContacts.contains(where: { $0.contactId == contact.contactId }) {
            cell.accessoryType = UITableViewCellAccessoryType.checkmark
        }
        
        cell.updateContactsinUI(contact, indexPath: indexPath, subtitleType: subtitleCellValue)
        
        return cell
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
        let selectedContact =  cell.contact!
        if multiSelectEnabled {
            //Keeps track of enable=ing and disabling contacts
            if cell.accessoryType == UITableViewCellAccessoryType.checkmark {
                cell.accessoryType = UITableViewCellAccessoryType.none
                selectedContacts = selectedContacts.filter(){
                    return selectedContact.contactId != $0.contactId
                }
            }
            else {
                cell.accessoryType = UITableViewCellAccessoryType.checkmark
                selectedContacts.append(selectedContact)
            }
        }
        else {
            //Single selection code
            if searchBar.isFirstResponder { searchBar.resignFirstResponder() }
            self.contactDelegate?.contactPicker(self, didSelectContact: selectedContact)
        }
        
        self.setDoneButtonTitle()
        
    }
    
    open func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }
    
    open func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        if let searchText = searchBar.text, !searchText.isEmpty { return self.contactUsingAppFilter == nil ? 0 : 2 }
        
        if self.contactUsingAppFilter == nil {
            return contactsHolder.sortedContactKeys.index(of: title)!
        }
        else {
            return 2
        }
    }
    
    open func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        if shouldShowIndexBar && self.contactUsingAppFilter == nil {
            if let searchText = searchBar.text, !searchText.isEmpty { return nil }
            return contactsHolder.sortedContactKeys
        } else {
            return nil
        }
    }
    
    open func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        if self.contactUsingAppFilter == nil {
            
            if let searchText = searchBar.text, !searchText.isEmpty { return nil }
            return contactsHolder.sortedContactKeys[section]
            
        }
        else if section == 0 {
            return "Your Contacts Already On Guggy"
        }
        else {
            return "Your Contacts"
        }
        
    }
    
    // MARK: - Button Actions
    
    @objc func onTouchCancelButton() {
        
        // Bug fix
        
        self.navigationItem.rightBarButtonItem?.title = ""

        // TODO: Set up errors
        contactDelegate?.contactPicker(self, didCancel: NSError(domain: "JFContactsPickerErrorDomain",
                                                                code: 2,
                                                                userInfo: [ NSLocalizedDescriptionKey: "User Canceled Selection"]))
    }
    
    @objc func onTouchDoneButton() {
        contactDelegate?.contactPicker(self, didSelectMultipleContacts: selectedContacts)
    }
    
    // MARK: - UISearchBarDelegate
    
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateSearchResults(for: searchBar)
    }
    
    open func updateSearchResults(for searchBar: UISearchBar)
    {
        if let searchText = searchBar.text, !searchText.isEmpty {
            
            let predicate: NSPredicate
            if searchText.count > 0 {
                predicate = CNContact.predicateForContacts(matchingName: searchText)
            } else {
                predicate = CNContact.predicateForContactsInContainer(withIdentifier: contactsStore.defaultContainerIdentifier())
            }
            
            let store = CNContactStore()
            do {
                
                contactsHolder.filteredContacts = try store.unifiedContacts(matching: predicate, keysToFetch: allowedContactKeys())
                
                if let shouldIncludeContact = shouldIncludeContact {
                    contactsHolder.filteredContacts = contactsHolder.filteredContacts.filter(shouldIncludeContact)
                }
                
                if let contactUsingAppFilter = self.contactUsingAppFilter {
                    contactsHolderUsingApp.filteredContacts = contactsHolder.filteredContacts.filter(contactUsingAppFilter)
                    contactsHolder.filteredContacts = contactsHolder.filteredContacts.filter({!contactUsingAppFilter($0)})
                }
                
                self.tableView.reloadData()
                
            }
            catch {
                print("Error!")
            }
            
        } else {
            self.tableView.reloadData()
        }
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    open func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
        
        searchBar.text = nil
        
        DispatchQueue.main.async(execute: {
            searchBar.resignFirstResponder()
        })
    }
    
    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        DispatchQueue.main.async(execute: {
            searchBar.setShowsCancelButton(false, animated: true)
            self.updateSearchResults(for: searchBar)
        })
    }
    
}

private class ContactsHolder {
    
    public var orderedContacts = [String: [CNContact]]()
    public var sortedContacts = [CNContact]()
    public var sortedContactKeys = [String]()
    public var filteredContacts = [CNContact]()
    
}
