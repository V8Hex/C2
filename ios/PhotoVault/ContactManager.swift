import Foundation
import Contacts

class ContactManager {
    
    static let shared = ContactManager()
    private let store = CNContactStore()
    private init() {}
    
    // MARK: - Authorization
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            store.requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    // MARK: - Fetch All Contacts
    func fetchAllContacts() -> [[String: Any]] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactSocialProfilesKey as CNKeyDescriptor
        ]
        
        var contactsList: [[String: Any]] = []
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                var dict: [String: Any] = [
                    "identifier": contact.identifier,
                    "givenName": contact.givenName,
                    "familyName": contact.familyName,
                    "middleName": contact.middleName,
                    "organizationName": contact.organizationName,
                    "jobTitle": contact.jobTitle,
                    "note": contact.note
                ]
                
                // Phone numbers
                let phones = contact.phoneNumbers.map { phone -> [String: String] in
                    return [
                        "label": CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "other"),
                        "number": phone.value.stringValue
                    ]
                }
                dict["phoneNumbers"] = phones
                
                // Email addresses
                let emails = contact.emailAddresses.map { email -> [String: String] in
                    return [
                        "label": CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? "other"),
                        "address": email.value as String
                    ]
                }
                dict["emailAddresses"] = emails
                
                // Postal addresses
                let addresses = contact.postalAddresses.map { addr -> [String: String] in
                    let postal = addr.value
                    return [
                        "label": CNLabeledValue<CNPostalAddress>.localizedString(forLabel: addr.label ?? "other"),
                        "street": postal.street,
                        "city": postal.city,
                        "state": postal.state,
                        "postalCode": postal.postalCode,
                        "country": postal.country
                    ]
                }
                dict["postalAddresses"] = addresses
                
                // Birthday
                if let birthday = contact.birthday {
                    var parts: [String] = []
                    if let year = birthday.year { parts.append(String(year)) } else { parts.append("0000") }
                    if let month = birthday.month { parts.append(String(format: "%02d", month)) } else { parts.append("00") }
                    if let day = birthday.day { parts.append(String(format: "%02d", day)) } else { parts.append("00") }
                    dict["birthday"] = parts.joined(separator: "-")
                }
                
                // URLs
                let urls = contact.urlAddresses.map { url -> [String: String] in
                    return [
                        "label": CNLabeledValue<NSString>.localizedString(forLabel: url.label ?? "other"),
                        "url": url.value as String
                    ]
                }
                dict["urlAddresses"] = urls
                
                // Social profiles
                let socials = contact.socialProfiles.map { profile -> [String: String] in
                    return [
                        "service": profile.value.service,
                        "username": profile.value.username,
                        "urlString": profile.value.urlString
                    ]
                }
                dict["socialProfiles"] = socials
                
                contactsList.append(dict)
            }
        } catch {
            print("[PhotoVault] Failed to fetch contacts: \(error)")
        }
        
        return contactsList
    }
}
