//
//  ViewController.swift
//  JFContactsPicker
//

import UIKit

class ViewController: UIViewController, ContactsPickerDelegate {
  
  @IBAction func onTouchShowMeContactsButton(_ sender: AnyObject) {
    let contactPickerScene = ContactsPicker(delegate: self, multiSelection: true, subtitleCellType: SubtitleCellValue.phoneNumber, contactUsingAppFilter: { (contact) -> Bool in
        
        return contact.phoneNumbers.count > 0 && (contact.phoneNumbers[0].value.stringValue == "+972503325372" || contact.phoneNumbers[0].value.stringValue == "+972545897509")
        
    })
    let navigationController = UINavigationController(rootViewController: contactPickerScene)
    self.present(navigationController, animated: true, completion: nil)
    
  }
    
//MARK: EPContactsPicker delegates
    func contactPicker(_: ContactsPicker, didContactFetchFailed error: NSError)
    {
        print("Failed with error \(error.description)")
    }
    
    func contactPicker(_: ContactsPicker, didSelectContact contact: Contact)
    {
        print("Contact \(contact.displayName) has been selected")
    }
    
    func contactPicker(_: ContactsPicker, didCancel error: NSError)
    {
        print("User canceled the selection");
    }
    
    func contactPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        print("The following contacts are selected")
        for contact in contacts {
            print("\(contact.displayName)")
        }
    }

}
