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
// - Replaced deprecated AddressBook framework (ABAddressBook, ABRecord, etc.)
//   with modern Contacts framework (CNContact, CNMutableContact, etc.)
// - Replaced ABPersonCreate / ABRecordRef with CNMutableContact
// - Replaced ABMultiValue with CNLabeledValue
// - Replaced kABPerson* constants with CN* equivalents
// - Removed manual CFRelease/CFRetain — now handled by ARC via Contacts framework
// - Replaced ABPersonCopyCompositeName with CNContactFormatter
// - Replaced ABPersonCopyImageData with CNContact.imageData
// - Replaced ABMultiValueGetCount / ABMultiValueGetIdentifierAtIndex with Swift array iteration

import Foundation
import Contacts

// MARK: - Error Codes

@objc enum CDVContactError: Int {
    case unknownError          = 0
    case invalidArgumentError  = 1
    case timeoutError          = 2
    case pendingOperationError = 3
    case ioError               = 4
    case notSupportedError     = 5
    case operationCancelledError = 6
    case permissionDeniedError = 20
}

// MARK: - W3C Field Name Constants

// Generic ContactField types
let kW3ContactFieldType    = "type"
let kW3ContactFieldValue   = "value"
let kW3ContactFieldPrimary = "pref"
let kW3ContactFieldId      = "id"

// Labels
let kW3ContactWorkLabel             = "work"
let kW3ContactHomeLabel             = "home"
let kW3ContactOtherLabel            = "other"
let kW3ContactPhoneWorkFaxLabel     = "work fax"
let kW3ContactPhoneHomeFaxLabel     = "home fax"
let kW3ContactPhoneMobileLabel      = "mobile"
let kW3ContactPhonePagerLabel       = "pager"
let kW3ContactPhoneIPhoneLabel      = "iphone"
let kW3ContactPhoneMainLabel        = "main"
let kW3ContactUrlBlog               = "blog"
let kW3ContactUrlProfile            = "profile"
let kW3ContactImAIMLabel            = "aim"
let kW3ContactImICQLabel            = "icq"
let kW3ContactImMSNLabel            = "msn"
let kW3ContactImYahooLabel          = "yahoo"
let kW3ContactImSkypeLabel          = "skype"
let kW3ContactImFacebookMessengerLabel = "facebook"
let kW3ContactImGoogleTalkLabel     = "gtalk"
let kW3ContactImJabberLabel         = "jabber"
let kW3ContactImQQLabel             = "qq"
let kW3ContactImGaduLabel           = "gadu"
let kW3ContactImType                = "type"
let kW3ContactImValue               = "value"

// Contact object keys
let kW3ContactId              = "id"
let kW3ContactName            = "name"
let kW3ContactFormattedName   = "formatted"
let kW3ContactGivenName       = "givenName"
let kW3ContactFamilyName      = "familyName"
let kW3ContactMiddleName      = "middleName"
let kW3ContactHonorificPrefix = "honorificPrefix"
let kW3ContactHonorificSuffix = "honorificSuffix"
let kW3ContactDisplayName     = "displayName"
let kW3ContactNickname        = "nickname"
let kW3ContactPhoneNumbers    = "phoneNumbers"
let kW3ContactAddresses       = "addresses"
let kW3ContactAddressFormatted = "formatted"
let kW3ContactStreetAddress   = "streetAddress"
let kW3ContactLocality        = "locality"
let kW3ContactRegion          = "region"
let kW3ContactPostalCode      = "postalCode"
let kW3ContactCountry         = "country"
let kW3ContactEmails          = "emails"
let kW3ContactIms             = "ims"
let kW3ContactOrganizations   = "organizations"
let kW3ContactOrganizationName = "name"
let kW3ContactTitle           = "title"
let kW3ContactDepartment      = "department"
let kW3ContactBirthday        = "birthday"
let kW3ContactNote            = "note"
let kW3ContactPhotos          = "photos"
let kW3ContactCategories      = "categories"
let kW3ContactUrls            = "urls"

// MARK: - CDVContact

/// Wraps a CNMutableContact and provides translation between
/// the W3C Contacts API dictionary format and the Contacts framework.
@objc class CDVContact: NSObject {

    // MARK: Properties

    /// The underlying Contacts-framework contact object.
    /// Previously an ABRecordRef; now a CNMutableContact managed by ARC.
    var contact: CNMutableContact

    /// Which fields to include when serialising back to JavaScript.
    var returnFields: [String: Any]?

    // MARK: - Static mapping tables

    /// Maps W3C field name → CNContact key path string (used for key fetching).
    static let w3cToContactKey: [String: String] = [
        kW3ContactGivenName:       CNContactGivenNameKey,
        kW3ContactFamilyName:      CNContactFamilyNameKey,
        kW3ContactMiddleName:      CNContactMiddleNameKey,
        kW3ContactHonorificPrefix: CNContactNamePrefixKey,
        kW3ContactHonorificSuffix: CNContactNameSuffixKey,
        kW3ContactNickname:        CNContactNicknameKey,
        kW3ContactOrganizationName:CNContactOrganizationNameKey,
        kW3ContactTitle:           CNContactJobTitleKey,
        kW3ContactDepartment:      CNContactDepartmentNameKey,
        kW3ContactNote:            CNContactNoteKey,
        kW3ContactPhoneNumbers:    CNContactPhoneNumbersKey,
        kW3ContactEmails:          CNContactEmailAddressesKey,
        kW3ContactUrls:            CNContactUrlAddressesKey,
        kW3ContactAddresses:       CNContactPostalAddressesKey,
        kW3ContactIms:             CNContactInstantMessageAddressesKey,
        kW3ContactBirthday:        CNContactBirthdayKey,
        kW3ContactPhotos:          CNContactImageDataKey,
        kW3ContactOrganizations:   CNContactOrganizationNameKey,
    ]

    // MARK: - Label mapping  (W3C ↔ CN label strings)

    static let w3cToCNLabel: [String: String] = [
        kW3ContactWorkLabel:             CNLabelWork,
        kW3ContactHomeLabel:             CNLabelHome,
        kW3ContactOtherLabel:            CNLabelOther,
        kW3ContactPhoneMobileLabel:      CNLabelPhoneNumberMobile,
        kW3ContactPhonePagerLabel:       CNLabelPhoneNumberPager,
        kW3ContactPhoneWorkFaxLabel:     CNLabelPhoneNumberWorkFax,
        kW3ContactPhoneHomeFaxLabel:     CNLabelPhoneNumberHomeFax,
        kW3ContactPhoneIPhoneLabel:      CNLabelPhoneNumberiPhone,
        kW3ContactPhoneMainLabel:        CNLabelPhoneNumberMain,
        kW3ContactImAIMLabel:            CNInstantMessageServiceAIM,
        kW3ContactImICQLabel:            CNInstantMessageServiceICQ,
        kW3ContactImMSNLabel:            CNInstantMessageServiceMSN,
        kW3ContactImYahooLabel:          CNInstantMessageServiceYahoo,
        kW3ContactImSkypeLabel:          CNInstantMessageServiceSkype,
        kW3ContactImGoogleTalkLabel:     CNInstantMessageServiceGoogleTalk,
        kW3ContactImFacebookMessengerLabel: CNInstantMessageServiceFacebook,
        kW3ContactImJabberLabel:         CNInstantMessageServiceJabber,
        kW3ContactImQQLabel:             CNInstantMessageServiceQQ,
        kW3ContactUrlProfile:            CNLabelURLAddressHomePage,
    ]

    // MARK: - Object & property definitions  (mirrors defaultObjectAndProperties)

    static let objectAndProperties: [String: [String]] = [
        kW3ContactName: [
            kW3ContactGivenName, kW3ContactFamilyName, kW3ContactMiddleName,
            kW3ContactHonorificPrefix, kW3ContactHonorificSuffix, kW3ContactFormattedName
        ],
        kW3ContactAddresses: [
            kW3ContactStreetAddress, kW3ContactLocality, kW3ContactRegion,
            kW3ContactPostalCode, kW3ContactCountry
        ],
        kW3ContactOrganizations: [
            kW3ContactOrganizationName, kW3ContactTitle, kW3ContactDepartment
        ],
        kW3ContactPhoneNumbers: [kW3ContactFieldType, kW3ContactFieldValue, kW3ContactFieldPrimary],
        kW3ContactEmails:       [kW3ContactFieldType, kW3ContactFieldValue, kW3ContactFieldPrimary],
        kW3ContactPhotos:       [kW3ContactFieldType, kW3ContactFieldValue, kW3ContactFieldPrimary],
        kW3ContactUrls:         [kW3ContactFieldType, kW3ContactFieldValue, kW3ContactFieldPrimary],
        kW3ContactIms:          [kW3ContactImValue, kW3ContactImType],
    ]

    /// Fields returned when caller requests "*" (all fields).
    static var defaultFields: [String: Any] {
        var d = [String: Any]()
        d[kW3ContactName]          = objectAndProperties[kW3ContactName]!
        d[kW3ContactNickname]      = NSNull()
        d[kW3ContactAddresses]     = objectAndProperties[kW3ContactAddresses]!
        d[kW3ContactOrganizations] = objectAndProperties[kW3ContactOrganizations]!
        d[kW3ContactPhoneNumbers]  = objectAndProperties[kW3ContactPhoneNumbers]!
        d[kW3ContactEmails]        = objectAndProperties[kW3ContactEmails]!
        d[kW3ContactIms]           = objectAndProperties[kW3ContactIms]!
        d[kW3ContactPhotos]        = objectAndProperties[kW3ContactPhotos]!
        d[kW3ContactUrls]          = objectAndProperties[kW3ContactUrls]!
        d[kW3ContactBirthday]      = NSNull()
        d[kW3ContactNote]          = NSNull()
        return d
    }

    // MARK: - Init

    /// Creates an empty contact (previously used ABPersonCreate).
    override init() {
        contact = CNMutableContact()
        super.init()
    }

    /// Wraps an existing CN contact.
    init(fromCNContact cnContact: CNContact) {
        contact = cnContact.mutableCopy() as! CNMutableContact
        super.init()
    }

    // MARK: - Label conversion helpers

    /// Converts a W3C label string to the corresponding CN label string.
    /// Falls back to the original label (custom label) if not found.
    static func convertContactTypeToCNLabel(_ label: String?) -> String {
        guard let label = label, !label.isEmpty else { return CNLabelOther }
        // Case-insensitive lookup
        for (w3cKey, cnLabel) in w3cToCNLabel {
            if w3cKey.caseInsensitiveCompare(label) == .orderedSame {
                return cnLabel
            }
        }
        return label // treat as custom label
    }

    /// Converts a CN label string back to the W3C label string.
    static func convertCNLabelToContactType(_ cnLabel: String?) -> String? {
        guard let cnLabel = cnLabel else { return nil }
        // Localise label if needed, then reverse-lookup
        let localized = CNLabeledValue<NSString>.localizedString(forLabel: cnLabel)
        for (w3cKey, mappedLabel) in w3cToCNLabel {
            if mappedLabel == cnLabel || mappedLabel.caseInsensitiveCompare(localized) == .orderedSame {
                return w3cKey
            }
        }
        return cnLabel // custom label
    }

    /// Returns true when the W3C label string matches a known type constant.
    static func isValidW3ContactType(_ label: String?) -> Bool {
        guard let label = label, !label.isEmpty else { return false }
        return w3cToCNLabel.keys.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }

    // MARK: - Return-field calculation

    /// Builds the returnFields dictionary from the JS `fields` array.
    static func calcReturnFields(_ fieldsArray: [Any]?) -> [String: Any]? {
        guard let fieldsArray = fieldsArray, !fieldsArray.isEmpty else { return nil }

        // Wildcard → return everything
        if fieldsArray.count == 1, let first = fieldsArray.first as? String, first == "*" {
            return defaultFields
        }

        var d = [String: Any]()

        for item in fieldsArray {
            // CB-7906: skip NSNull entries
            if item is NSNull { continue }

            let fieldStr: String
            if let n = item as? NSNumber { fieldStr = n.stringValue }
            else if let s = item as? String { fieldStr = s }
            else { continue }

            // Support "object.property" notation
            let parts = fieldStr.components(separatedBy: ".")
            let name = parts[0]
            let property = parts.count > 1 ? parts[1] : nil

            if let fields = objectAndProperties[name] {
                if let property = property {
                    // Individual sub-property e.g. "name.givenName"
                    if w3cToContactKey[property] != nil {
                        var arr = d[name] as? [String] ?? []
                        if !arr.contains(property) { arr.append(property) }
                        d[name] = arr
                    }
                } else {
                    // Full object
                    d[name] = fields
                }
            } else {
                // Simple top-level property
                if w3cToContactKey[name] != nil || name == kW3ContactDisplayName ||
                   name == kW3ContactCategories || name == kW3ContactFormattedName {
                    d[name] = NSNull()
                }
            }
        }

        return d.isEmpty ? nil : d
    }

    // MARK: - Populate contact from W3C dictionary

    /// Applies values from a JavaScript Contact dictionary to the underlying CNMutableContact.
    /// `asUpdate: true` means existing values should be preserved/removed selectively.
    @discardableResult
    func setFromContactDict(_ aContact: [String: Any], asUpdate bUpdate: Bool) -> Bool {
        // --- Name ---
        var hasName = false

        if let nameDict = aContact[kW3ContactName] as? [String: Any] {
            hasName = true
            contact.givenName       = nameDict[kW3ContactGivenName]       as? String ?? contact.givenName
            contact.familyName      = nameDict[kW3ContactFamilyName]      as? String ?? contact.familyName
            contact.middleName      = nameDict[kW3ContactMiddleName]       as? String ?? contact.middleName
            contact.namePrefix      = nameDict[kW3ContactHonorificPrefix]  as? String ?? contact.namePrefix
            contact.nameSuffix      = nameDict[kW3ContactHonorificSuffix]  as? String ?? contact.nameSuffix
            // kW3ContactFormattedName is read-only (computed by CNContactFormatter)
        }

        if let nickname = aContact[kW3ContactNickname] as? String {
            hasName = true
            contact.nickname = nickname
        } else if !hasName, let displayName = aContact[kW3ContactDisplayName] as? String {
            contact.nickname = displayName
        }

        // --- Phone numbers ---
        if let phones = aContact[kW3ContactPhoneNumbers] as? [[String: Any]] {
            contact.phoneNumbers = phones.compactMap { dict -> CNLabeledValue<CNPhoneNumber>? in
                guard let value = dict[kW3ContactFieldValue] as? String, !value.isEmpty else { return nil }
                let label = CDVContact.convertContactTypeToCNLabel(dict[kW3ContactFieldType] as? String)
                return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: value))
            }
        }

        // --- Emails ---
        if let emails = aContact[kW3ContactEmails] as? [[String: Any]] {
            contact.emailAddresses = emails.compactMap { dict -> CNLabeledValue<NSString>? in
                guard let value = dict[kW3ContactFieldValue] as? String, !value.isEmpty else { return nil }
                let label = CDVContact.convertContactTypeToCNLabel(dict[kW3ContactFieldType] as? String)
                return CNLabeledValue(label: label, value: value as NSString)
            }
        }

        // --- URLs ---
        if let urls = aContact[kW3ContactUrls] as? [[String: Any]] {
            contact.urlAddresses = urls.compactMap { dict -> CNLabeledValue<NSString>? in
                guard let value = dict[kW3ContactFieldValue] as? String, !value.isEmpty else { return nil }
                let label = CDVContact.convertContactTypeToCNLabel(dict[kW3ContactFieldType] as? String)
                return CNLabeledValue(label: label, value: value as NSString)
            }
        }

        // --- Addresses ---
        if let addresses = aContact[kW3ContactAddresses] as? [[String: Any]] {
            contact.postalAddresses = addresses.compactMap { dict -> CNLabeledValue<CNPostalAddress>? in
                let addr = CNMutablePostalAddress()
                addr.street     = dict[kW3ContactStreetAddress] as? String ?? ""
                addr.city       = dict[kW3ContactLocality]      as? String ?? ""
                addr.state      = dict[kW3ContactRegion]        as? String ?? ""
                addr.postalCode = dict[kW3ContactPostalCode]    as? String ?? ""
                addr.country    = dict[kW3ContactCountry]       as? String ?? ""
                let label = CDVContact.convertContactTypeToCNLabel(dict[kW3ContactFieldType] as? String)
                return CNLabeledValue(label: label, value: addr)
            }
        }

        // --- Instant Messages ---
        if let ims = aContact[kW3ContactIms] as? [[String: Any]] {
            contact.instantMessageAddresses = ims.compactMap { dict -> CNLabeledValue<CNInstantMessageAddress>? in
                guard let username = dict[kW3ContactImValue] as? String, !username.isEmpty else { return nil }
                let service = CDVContact.convertContactTypeToCNLabel(dict[kW3ContactImType] as? String)
                let im = CNInstantMessageAddress(username: username, service: service)
                return CNLabeledValue(label: CNLabelOther, value: im)
            }
        }

        // --- Organizations (iOS supports one) ---
        if let orgs = aContact[kW3ContactOrganizations] as? [[String: Any]] {
            if orgs.isEmpty {
                contact.organizationName = ""
                contact.jobTitle = ""
                contact.departmentName = ""
            } else if let first = orgs.first {
                contact.organizationName = first[kW3ContactOrganizationName] as? String ?? ""
                contact.jobTitle         = first[kW3ContactTitle]            as? String ?? ""
                contact.departmentName   = first[kW3ContactDepartment]       as? String ?? ""
            }
        }

        // --- Birthday ---
        // Comes in as milliseconds since epoch (NSNumber) or ISO string
        if let ms = aContact[kW3ContactBirthday] as? NSNumber {
            let date = Date(timeIntervalSince1970: ms.doubleValue / 1000.0)
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            comps.hour = nil; comps.minute = nil; comps.second = nil
            contact.birthday = comps
        } else if let dateStr = aContact[kW3ContactBirthday] as? String {
            let fmt = ISO8601DateFormatter()
            if let date = fmt.date(from: dateStr) {
                contact.birthday = Calendar.current.dateComponents([.year, .month, .day], from: date)
            }
        }

        // --- Note ---
        if let note = aContact[kW3ContactNote] as? String {
            contact.note = note
        }

        // --- Photo ---
        if let photos = aContact[kW3ContactPhotos] as? [[String: Any]] {
            if bUpdate && photos.isEmpty {
                contact.imageData = nil
            } else if let first = photos.first, let urlStr = first[kW3ContactFieldValue] as? String {
                if bUpdate && urlStr.isEmpty {
                    contact.imageData = nil
                } else {
                    let clean = urlStr.removingPercentEncoding ?? urlStr
                    if let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: encoded),
                       let data = try? Data(contentsOf: url), !data.isEmpty {
                        contact.imageData = data
                    }
                }
            }
        }

        return true
    }

    // MARK: - Serialise contact → W3C dictionary

    /// Produces the JavaScript-facing dictionary for this contact.
    func toDictionary(withFields fields: [String: Any]?) -> [String: Any] {
        var nc = [String: Any]()
        nc[kW3ContactId] = contact.identifier

        guard let fields = fields else { return nc }
        self.returnFields = fields

        // displayName (not natively supported; derive from formatter)
        if fields[kW3ContactDisplayName] != nil {
            nc[kW3ContactDisplayName] = NSNull()
        }

        // Nickname
        if fields[kW3ContactNickname] != nil {
            nc[kW3ContactNickname] = contact.nickname.isEmpty ? NSNull() : contact.nickname
        }

        // Name object
        if let nameData = extractName() {
            nc[kW3ContactName] = nameData
            // Fill displayName if still null
            if fields[kW3ContactDisplayName] != nil,
               let formatted = (nameData as? [String: Any])?[kW3ContactFormattedName] as? String,
               !formatted.isEmpty {
                nc[kW3ContactDisplayName] = formatted
            }
        }

        // Fallback displayName from formatter
        if fields[kW3ContactDisplayName] != nil, nc[kW3ContactDisplayName] is NSNull {
            let formatted = CNContactFormatter.string(from: contact, style: .fullName)
            nc[kW3ContactDisplayName] = formatted ?? (contact.nickname.isEmpty ? "" : contact.nickname)
        }

        if let phones = extractMultiValueStrings(kW3ContactPhoneNumbers) {
            nc[kW3ContactPhoneNumbers] = phones
        }
        if let emails = extractMultiValueStrings(kW3ContactEmails) {
            nc[kW3ContactEmails] = emails
        }
        if let urls = extractMultiValueStrings(kW3ContactUrls) {
            nc[kW3ContactUrls] = urls
        }
        if let addrs = extractAddresses() {
            nc[kW3ContactAddresses] = addrs
        }
        if let ims = extractIms() {
            nc[kW3ContactIms] = ims
        }
        if let orgs = extractOrganizations() {
            nc[kW3ContactOrganizations] = orgs
        }

        // Birthday → milliseconds since epoch
        if fields[kW3ContactBirthday] != nil {
            if let bday = contact.birthday,
               let date = Calendar.current.date(from: bday) {
                nc[kW3ContactBirthday] = NSNumber(value: date.timeIntervalSince1970 * 1000)
            }
        }

        // Note
        if fields[kW3ContactNote] != nil {
            nc[kW3ContactNote] = contact.note.isEmpty ? NSNull() : contact.note
        }

        // Photos
        if fields[kW3ContactPhotos] != nil {
            nc[kW3ContactPhotos] = extractPhotos() ?? NSNull()
        }

        return nc
    }

    // MARK: - Extraction helpers

    private func extractName() -> Any? {
        guard let fields = returnFields?[kW3ContactName] as? [String] else { return nil }

        var nameDict = [String: Any]()

        for field in fields {
            switch field {
            case kW3ContactFormattedName:
                let formatted = CNContactFormatter.string(from: contact, style: .fullName)
                nameDict[field] = formatted ?? NSNull()
            case kW3ContactGivenName:
                nameDict[field] = contact.givenName.isEmpty ? NSNull() : contact.givenName
            case kW3ContactFamilyName:
                nameDict[field] = contact.familyName.isEmpty ? NSNull() : contact.familyName
            case kW3ContactMiddleName:
                nameDict[field] = contact.middleName.isEmpty ? NSNull() : contact.middleName
            case kW3ContactHonorificPrefix:
                nameDict[field] = contact.namePrefix.isEmpty ? NSNull() : contact.namePrefix
            case kW3ContactHonorificSuffix:
                nameDict[field] = contact.nameSuffix.isEmpty ? NSNull() : contact.nameSuffix
            default: break
            }
        }

        return nameDict.isEmpty ? nil : nameDict
    }

    /// Extracts phone numbers, emails, or URL arrays (CNLabeledValue<NSString / CNPhoneNumber>).
    private func extractMultiValueStrings(_ propertyId: String) -> Any? {
        guard let fields = returnFields?[propertyId] as? [String] else { return nil }

        var results = [[String: Any]]()

        func addEntry(identifier: String, label: String?, value: String) {
            var dict = [String: Any]()
            if fields.contains(kW3ContactFieldType) {
                dict[kW3ContactFieldType] = CDVContact.convertCNLabelToContactType(label) ?? NSNull()
            }
            if fields.contains(kW3ContactFieldValue) {
                dict[kW3ContactFieldValue] = value
            }
            if fields.contains(kW3ContactFieldPrimary) {
                dict[kW3ContactFieldPrimary] = false
            }
            dict[kW3ContactFieldId] = identifier
            results.append(dict)
        }

        switch propertyId {
        case kW3ContactPhoneNumbers:
            for lv in contact.phoneNumbers {
                addEntry(identifier: lv.identifier, label: lv.label, value: lv.value.stringValue)
            }
        case kW3ContactEmails:
            for lv in contact.emailAddresses {
                addEntry(identifier: lv.identifier, label: lv.label, value: lv.value as String)
            }
        case kW3ContactUrls:
            for lv in contact.urlAddresses {
                addEntry(identifier: lv.identifier, label: lv.label, value: lv.value as String)
            }
        default: break
        }

        return results.isEmpty ? NSNull() : results
    }

    private func extractAddresses() -> Any? {
        guard let fields = returnFields?[kW3ContactAddresses] as? [String] else { return nil }

        if contact.postalAddresses.isEmpty { return NSNull() }

        return contact.postalAddresses.map { lv -> [String: Any] in
            let addr = lv.value
            var dict: [String: Any] = [kW3ContactFieldId: lv.identifier]
            dict[kW3ContactFieldType]    = CDVContact.convertCNLabelToContactType(lv.label) ?? NSNull()
            dict[kW3ContactFieldPrimary] = "false"

            for field in fields {
                switch field {
                case kW3ContactStreetAddress: dict[field] = addr.street.isEmpty   ? NSNull() : addr.street
                case kW3ContactLocality:      dict[field] = addr.city.isEmpty     ? NSNull() : addr.city
                case kW3ContactRegion:        dict[field] = addr.state.isEmpty    ? NSNull() : addr.state
                case kW3ContactPostalCode:    dict[field] = addr.postalCode.isEmpty ? NSNull() : addr.postalCode
                case kW3ContactCountry:       dict[field] = addr.country.isEmpty  ? NSNull() : addr.country
                default:                      dict[field] = NSNull()
                }
            }
            return dict
        }
    }

    private func extractIms() -> Any? {
        guard let fields = returnFields?[kW3ContactIms] as? [String] else { return nil }

        if contact.instantMessageAddresses.isEmpty { return NSNull() }

        return contact.instantMessageAddresses.map { lv -> [String: Any] in
            let im = lv.value
            var dict: [String: Any] = [kW3ContactFieldId: lv.identifier]
            if fields.contains(kW3ContactFieldValue) {
                dict[kW3ContactFieldValue] = im.username.isEmpty ? NSNull() : im.username
            }
            if fields.contains(kW3ContactFieldType) {
                dict[kW3ContactFieldType] = CDVContact.convertCNLabelToContactType(im.service) ?? NSNull()
            }
            return dict
        }
    }

    private func extractOrganizations() -> Any? {
        guard let fields = returnFields?[kW3ContactOrganizations] as? [String] else { return nil }

        let hasOrg = !contact.organizationName.isEmpty
        let hasTitle = !contact.jobTitle.isEmpty
        let hasDept = !contact.departmentName.isEmpty

        guard hasOrg || hasTitle || hasDept else { return NSNull() }

        var dict: [String: Any] = [
            kW3ContactFieldPrimary: "false",
            kW3ContactFieldType:    NSNull()
        ]
        for field in fields {
            switch field {
            case kW3ContactOrganizationName:
                dict[field] = contact.organizationName.isEmpty ? NSNull() : contact.organizationName
            case kW3ContactTitle:
                dict[field] = contact.jobTitle.isEmpty ? NSNull() : contact.jobTitle
            case kW3ContactDepartment:
                dict[field] = contact.departmentName.isEmpty ? NSNull() : contact.departmentName
            default:
                dict[field] = NSNull()
            }
        }
        return [dict]
    }

    private func extractPhotos() -> Any? {
        guard let imageData = contact.imageData, !imageData.isEmpty else { return nil }

        let photoId = contact.identifier
        let filePath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("contact_photo_\(photoId)")

        do {
            try imageData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            NSLog("Error writing contact photo: \(error.localizedDescription)")
            return nil
        }

        return [[
            kW3ContactFieldValue:   filePath,
            kW3ContactFieldType:    "url",
            kW3ContactFieldPrimary: "false"
        ]]
    }

    // MARK: - Search

    /// Returns true if `testValue` appears in any of the `searchFields` for this contact.
    func foundValue(_ testValue: String, inFields searchFields: [String: Any]) -> Bool {
        guard !testValue.isEmpty else { return false }

        // Always search by identifier
        if contact.identifier == testValue { return true }

        // Nickname
        if searchFields[kW3ContactNickname] != nil,
           contact.nickname.range(of: testValue, options: .caseInsensitive) != nil {
            return true
        }

        // Name fields
        if let nameFields = searchFields[kW3ContactName] as? [String] {
            for field in nameFields {
                let str: String
                switch field {
                case kW3ContactFormattedName:
                    str = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                case kW3ContactGivenName:       str = contact.givenName
                case kW3ContactFamilyName:      str = contact.familyName
                case kW3ContactMiddleName:      str = contact.middleName
                case kW3ContactHonorificPrefix: str = contact.namePrefix
                case kW3ContactHonorificSuffix: str = contact.nameSuffix
                default: continue
                }
                if str.range(of: testValue, options: .caseInsensitive) != nil { return true }
            }
        }

        // Phone numbers
        if let phoneFields = searchFields[kW3ContactPhoneNumbers] as? [String] {
            for lv in contact.phoneNumbers {
                if phoneFields.contains(kW3ContactFieldValue),
                   lv.value.stringValue.range(of: testValue, options: .caseInsensitive) != nil {
                    return true
                }
                if phoneFields.contains(kW3ContactFieldType),
                   CDVContact.isValidW3ContactType(testValue),
                   let label = lv.label,
                   CDVContact.convertContactTypeToCNLabel(testValue) == label {
                    return true
                }
            }
        }

        // Emails
        if let emailFields = searchFields[kW3ContactEmails] as? [String] {
            for lv in contact.emailAddresses {
                if emailFields.contains(kW3ContactFieldValue),
                   (lv.value as String).range(of: testValue, options: .caseInsensitive) != nil {
                    return true
                }
            }
        }

        // Addresses
        if let addrFields = searchFields[kW3ContactAddresses] as? [String] {
            for lv in contact.postalAddresses {
                let addr = lv.value
                let candidates: [String] = [addr.street, addr.city, addr.state, addr.postalCode, addr.country]
                for c in candidates where !c.isEmpty {
                    if c.range(of: testValue, options: .caseInsensitive) != nil { return true }
                }
                _ = addrFields // suppress unused warning — all address sub-fields searched above
            }
        }

        // IMs
        if let imFields = searchFields[kW3ContactIms] as? [String] {
            for lv in contact.instantMessageAddresses {
                let im = lv.value
                if imFields.contains(kW3ContactImValue),
                   im.username.range(of: testValue, options: .caseInsensitive) != nil {
                    return true
                }
                if imFields.contains(kW3ContactImType),
                   CDVContact.isValidW3ContactType(testValue),
                   CDVContact.convertContactTypeToCNLabel(testValue) == im.service {
                    return true
                }
            }
        }

        // Organizations
        if let orgFields = searchFields[kW3ContactOrganizations] as? [String] {
            let candidates: [(String, String)] = [
                (kW3ContactOrganizationName, contact.organizationName),
                (kW3ContactTitle,            contact.jobTitle),
                (kW3ContactDepartment,       contact.departmentName)
            ]
            for (field, value) in candidates where orgFields.contains(field) {
                if value.range(of: testValue, options: .caseInsensitive) != nil { return true }
            }
        }

        // Note
        if searchFields[kW3ContactNote] != nil,
           contact.note.range(of: testValue, options: .caseInsensitive) != nil {
            return true
        }

        // Birthday
        if searchFields[kW3ContactBirthday] != nil,
           let bday = contact.birthday,
           let date = Calendar.current.date(from: bday) {
            let dateStr = date.description(with: Locale.current)
            if dateStr.range(of: testValue, options: .caseInsensitive) != nil { return true }
        }

        // URLs
        if let urlFields = searchFields[kW3ContactUrls] as? [String] {
            for lv in contact.urlAddresses {
                if urlFields.contains(kW3ContactFieldValue),
                   (lv.value as String).range(of: testValue, options: .caseInsensitive) != nil {
                    return true
                }
            }
        }

        return false
    }
}
