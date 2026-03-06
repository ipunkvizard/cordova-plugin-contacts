/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

// MIGRATION NOTES:
// - Replaced ABPeoplePickerNavigationController   → CNContactPickerViewController
// - Replaced ABNewPersonViewController            → CNContactViewController (for new contact)
// - Replaced ABPersonViewController              → CNContactViewController
// - Replaced ABAddressBookRef / ABAddressBookCreate → CNContactStore
// - Replaced ABAddressBookCopyArrayOfAllPeople    → CNContactStore.enumerateContacts(with:)
// - Replaced ABAddressBookRequestAccessWithCompletion → CNContactStore.requestAccess(for:)
// - Replaced ABAddressBookGetPersonWithRecordID   → CNContactStore.unifiedContact(withIdentifier:)
// - Replaced ABAddressBookAddRecord / ABAddressBookSave → CNSaveRequest
// - Replaced ABAddressBookRemoveRecord            → CNSaveRequest.delete()
// - Removed all manual CFRelease / CFRetain calls
// - ABAuthorizationStatus → CNAuthorizationStatus

import Foundation
import Contacts
import ContactsUI
import Cordova

// MARK: - CDVContacts Plugin

@objc(CDVContacts)
class CDVContacts: CDVPlugin {

    private let store = CNContactStore()

    // MARK: - New Contact GUI  (iOS-specific, not W3C)

    @objc(newContact:)
    func newContact(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId!

        requestAccess { [weak self] granted in
            guard let self = self, granted else {
                // Permission denied — return without error callback (matches original behaviour)
                return
            }
            DispatchQueue.main.async {
                let newVC = CDVNewContactViewController()
                newVC.contactStore = self.store
                newVC.delegate = newVC          // CDVNewContactViewController is its own delegate
                newVC.cdvCallbackId = callbackId
                newVC.cdvPlugin = self

                let nav = UINavigationController(rootViewController: newVC)
                self.viewController.present(nav, animated: true)
            }
        }
    }

    // MARK: - Display Contact  (iOS-specific)

    @objc(displayContact:)
    func displayContact(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId!
        let recordId   = command.argument(at: 0) as? String ?? ""
        let options    = command.argument(at: 1) as? [String: Any]
        let allowsEditing = (options?["allowsEditing"] as? String)?.lowercased() == "true"

        requestAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.sendError(.permissionDeniedError, callbackId: callbackId)
                return
            }
            do {
                let keysToFetch = CDVContacts.allCNKeys()
                let contact = try self.store.unifiedContact(withIdentifier: recordId,
                                                            keysToFetch: keysToFetch)
                DispatchQueue.main.async {
                    let vc = CDVDisplayContactViewController(for: contact, store: self.store)
                    vc.allowsEditing = allowsEditing
                    vc.cdvPlugin = self

                    let parent = UIViewController()
                    let nav    = UINavigationController(rootViewController: parent)
                    nav.pushViewController(vc, animated: false)
                    self.viewController.present(nav, animated: true)

                    if allowsEditing {
                        let editVC = CNContactViewController(for: contact)
                        editVC.contactStore = self.store
                        editVC.allowsEditing = true
                        nav.pushViewController(editVC, animated: true)
                    }
                }
            } catch {
                self.sendError(.unknownError, callbackId: callbackId)
            }
        }
    }

    // MARK: - Choose Contact  (iOS-specific)

    @objc(chooseContact:)
    func chooseContact(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId!
        let options    = command.argument(at: 0) as? [String: Any]
        let fields     = options?["fields"] as? [Any]
        let allowsEditing = (options?["allowsEditing"] as? NSNumber)?.boolValue ?? false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let picker = CDVContactsPicker()
            picker.cdvCallbackId  = callbackId
            picker.cdvPlugin      = self
            picker.cdvFields      = fields
            picker.cdvAllowsEditing = allowsEditing
            picker.delegate       = picker
            self.viewController.present(picker, animated: true)
        }
    }

    // MARK: - Pick Contact (W3C-compatible)

    @objc(pickContact:)
    func pickContact(_ command: CDVInvokedUrlCommand) {
        var desiredFields = command.argument(at: 0) as? [Any] ?? []
        if desiredFields.isEmpty { desiredFields = ["*"] }

        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            let opts: [String: Any] = ["fields": desiredFields, "allowsEditing": false]
            let synth = CDVInvokedUrlCommand(arguments: [opts],
                                             callbackId: command.callbackId,
                                             className: command.className,
                                             methodName: command.methodName)
            chooseContact(synth!)
        case .restricted, .denied:
            sendError(.permissionDeniedError, callbackId: command.callbackId!)
        default: // .notDetermined
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                guard let self = self else { return }
                if granted {
                    let opts: [String: Any] = ["fields": desiredFields, "allowsEditing": false]
                    let synth = CDVInvokedUrlCommand(arguments: [opts],
                                                     callbackId: command.callbackId,
                                                     className: command.className,
                                                     methodName: command.methodName)
                    self.chooseContact(synth!)
                } else {
                    self.sendError(.permissionDeniedError, callbackId: command.callbackId!)
                }
            }
        }
    }

    // MARK: - Search

    @objc(search:)
    func search(_ command: CDVInvokedUrlCommand) {
        let callbackId   = command.callbackId!
        let fields       = command.argument(at: 0) as? [Any] ?? []
        let findOptions  = command.argument(at: 1) as? [String: Any]

        commandDelegate.run(inBackground: { [weak self] in
            guard let self = self else { return }

            self.requestAccess { granted in
                guard granted else {
                    self.sendError(.permissionDeniedError, callbackId: callbackId)
                    return
                }

                // Parse find options
                var filterStr: String? = nil
                var multiple = false
                var desiredFields: [Any] = ["*"]

                if let fo = findOptions {
                    if let fv = fo["filter"] as? NSNumber { filterStr = fv.stringValue }
                    else if let fv = fo["filter"] as? String, !fv.isEmpty { filterStr = fv }
                    multiple = (fo["multiple"] as? NSNumber)?.boolValue ?? false
                    if let df = fo["desiredFields"] as? [Any], !df.isEmpty { desiredFields = df }
                }

                let searchFields  = CDVContact.calcReturnFields(fields) ?? [:]
                let returnFields  = CDVContact.calcReturnFields(desiredFields)
                let keysToFetch   = CDVContacts.allCNKeys()

                do {
                    var matches: [CDVContact] = []
                    let request = CNContactFetchRequest(keysToFetch: keysToFetch)

                    try self.store.enumerateContacts(with: request) { cnContact, stop in
                        let cdvContact = CDVContact(fromCNContact: cnContact)
                        if let filter = filterStr, !filter.isEmpty {
                            if cdvContact.foundValue(filter, inFields: searchFields) {
                                matches.append(cdvContact)
                            }
                        } else {
                            matches.append(cdvContact)
                        }
                        if !multiple && matches.count == 1 { stop.pointee = true }
                    }

                    let count = multiple ? matches.count : min(matches.count, 1)
                    let returnContacts = matches.prefix(count).map { $0.toDictionary(withFields: returnFields) }

                    let result = CDVPluginResult(status: .ok, messageAs: Array(returnContacts))
                    self.commandDelegate.send(result, callbackId: callbackId)

                } catch {
                    self.sendError(.ioError, callbackId: callbackId)
                }
            }
        })
    }

    // MARK: - Save

    @objc(save:)
    func save(_ command: CDVInvokedUrlCommand) {
        let callbackId  = command.callbackId!
        guard let contactDict = command.argument(at: 0) as? [String: Any] else {
            sendError(.invalidArgumentError, callbackId: callbackId); return
        }

        commandDelegate.run(inBackground: { [weak self] in
            guard let self = self else { return }

            self.requestAccess { granted in
                guard granted else {
                    self.sendError(.permissionDeniedError, callbackId: callbackId); return
                }

                let existingId = contactDict[kW3ContactId] as? String
                let saveRequest = CNSaveRequest()
                var cdvContact: CDVContact

                if let eid = existingId, !eid.isEmpty {
                    // Update existing contact
                    do {
                        let keys = CDVContacts.allCNKeys()
                        let existing = try self.store.unifiedContact(withIdentifier: eid, keysToFetch: keys)
                        cdvContact = CDVContact(fromCNContact: existing)
                        cdvContact.setFromContactDict(contactDict, asUpdate: true)
                        saveRequest.update(cdvContact.contact)
                    } catch {
                        self.sendError(.ioError, callbackId: callbackId); return
                    }
                } else {
                    // New contact
                    cdvContact = CDVContact()
                    cdvContact.setFromContactDict(contactDict, asUpdate: false)
                    saveRequest.add(cdvContact.contact, toContainerWithIdentifier: nil)
                }

                do {
                    try self.store.execute(saveRequest)
                    let result = cdvContact.toDictionary(withFields: CDVContact.defaultFields)
                    let pluginResult = CDVPluginResult(status: .ok, messageAs: result)
                    self.commandDelegate.send(pluginResult, callbackId: callbackId)
                } catch {
                    self.sendError(.ioError, callbackId: callbackId)
                }
            }
        })
    }

    // MARK: - Remove

    @objc(remove:)
    func remove(_ command: CDVInvokedUrlCommand) {
        let callbackId = command.callbackId!
        guard let contactId = command.argument(at: 0) as? String, !contactId.isEmpty else {
            sendError(.invalidArgumentError, callbackId: callbackId); return
        }

        requestAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else { self.sendError(.permissionDeniedError, callbackId: callbackId); return }

            do {
                let keys    = CDVContacts.allCNKeys()
                let contact = try self.store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
                let mutable = contact.mutableCopy() as! CNMutableContact
                let req     = CNSaveRequest()
                req.delete(mutable)
                try self.store.execute(req)
                let result = CDVPluginResult(status: .ok)
                self.commandDelegate.send(result, callbackId: callbackId)
            } catch {
                self.sendError(.unknownError, callbackId: callbackId)
            }
        }
    }

    // MARK: - Helpers

    private func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            completion(true)
        case .restricted, .denied:
            completion(false)
        default:
            store.requestAccess(for: .contacts) { granted, _ in completion(granted) }
        }
    }

    func sendError(_ code: CDVContactError, callbackId: String) {
        let result = CDVPluginResult(status: .error, messageAs: code.rawValue)
        commandDelegate.send(result, callbackId: callbackId)
    }

    /// Returns all CN descriptor keys needed to populate every W3C field.
    static func allCNKeys() -> [CNKeyDescriptor] {
        return [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNamePrefixKey as CNKeyDescriptor,
            CNContactNameSuffixKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactInstantMessageAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
    }
}

// MARK: - CDVContactsPicker  (replaces ABPeoplePickerNavigationController subclass)

/// Wraps CNContactPickerViewController to provide the iOS people-picker UI.
class CDVContactsPicker: CNContactPickerViewController, CNContactPickerDelegate {

    var cdvCallbackId: String?
    weak var cdvPlugin: CDVContacts?
    var cdvFields: [Any]?
    var cdvAllowsEditing: Bool = false

    // CNContactPickerDelegate — user cancelled
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        let result = CDVPluginResult(status: .error, messageAs: CDVContactError.operationCancelledError.rawValue)
        cdvPlugin?.commandDelegate.send(result, callbackId: cdvCallbackId)
    }

    // CNContactPickerDelegate — user selected a contact
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        guard let plugin = cdvPlugin, let callbackId = cdvCallbackId else { return }

        if cdvAllowsEditing {
            // Push edit view on top of existing nav stack
            DispatchQueue.main.async {
                let editVC = CNContactViewController(for: contact)
                editVC.contactStore = plugin.store
                editVC.allowsEditing = true
                // Wrap in nav since CNContactPickerViewController dismisses itself
                let nav = UINavigationController(rootViewController: editVC)
                plugin.viewController.present(nav, animated: true)
            }
        } else {
            let returnFields = CDVContact.calcReturnFields(cdvFields)
            let cdv = CDVContact(fromCNContact: contact)
            let dict = cdv.toDictionary(withFields: returnFields)
            let result = CDVPluginResult(status: .ok, messageAs: dict)
            plugin.commandDelegate.send(result, callbackId: callbackId)
        }
    }
}

// MARK: - CDVNewContactViewController  (replaces ABNewPersonViewController subclass)

/// Hosts CNContactViewController in "new contact" mode.
class CDVNewContactViewController: CNContactViewController, CNContactViewControllerDelegate {

    var cdvCallbackId: String?
    weak var cdvPlugin: CDVContacts?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    // CNContactViewControllerDelegate
    func contactViewController(_ viewController: CNContactViewController,
                                didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            let result: CDVPluginResult
            if let contact = contact {
                result = CDVPluginResult(status: .ok, messageAs: contact.identifier)
            } else {
                result = CDVPluginResult(status: .ok, messageAs: -1)
            }
            self.cdvPlugin?.commandDelegate.send(result, callbackId: self.cdvCallbackId)
        }
    }
}

// MARK: - CDVDisplayContactViewController  (replaces ABPersonViewController subclass)

/// Displays a contact and dismisses the entire nav stack on back.
class CDVDisplayContactViewController: CNContactViewController {

    weak var cdvPlugin: CDVContacts?

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presentingViewController?.dismiss(animated: true)
    }
}
