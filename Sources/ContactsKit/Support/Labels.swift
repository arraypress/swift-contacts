//
//  Labels.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  Turning the framework's label constants into words, and back.
//
//  `CNLabelPhoneNumberMobile` is the string `_$!<Mobile>!$_`. Those delimiters
//  are how the system recognises a label it should localise and give an icon
//  to, so they cannot be trimmed on the way in and re-invented on the way out:
//  a contact saved with `Mobile` instead of `_$!<Mobile>!$_` shows in Contacts
//  with the label spelled out in English for every user, in every language,
//  and loses the little handset.
//
//  So the rule here is: read leniently, write the constant wherever one exists,
//  and pass anything custom through untouched.
//

import Contacts
import Foundation

/// Reads and writes the framework's label constants.
public enum Labels {

    /// Every label the framework names, keyed by the word a person would type.
    ///
    /// Built from the constants rather than from their spellings, so it stays
    /// correct if Apple ever changes the encoding.
    public static var known: [String: String] {
        var table: [String: String] = [
            "home": CNLabelHome,
            "work": CNLabelWork,
            "school": CNLabelSchool,
            "other": CNLabelOther,
            "mobile": CNLabelPhoneNumberMobile,
            "iphone": CNLabelPhoneNumberiPhone,
            "main": CNLabelPhoneNumberMain,
            "homefax": CNLabelPhoneNumberHomeFax,
            "workfax": CNLabelPhoneNumberWorkFax,
            "otherfax": CNLabelPhoneNumberOtherFax,
            "pager": CNLabelPhoneNumberPager,
            "applewatch": CNLabelPhoneNumberAppleWatch,
            "anniversary": CNLabelDateAnniversary,
            "icloud": CNLabelEmailiCloud,
            "homepage": CNLabelURLAddressHomePage
        ]
        // Relations are labels too. The framework declares around two hundred
        // of them — kinship terms precise enough to distinguish a father's
        // elder brother's wife from a mother's younger sister — and this is
        // the handful anyone types. Everything else still works: an unknown
        // word becomes a custom label, which is exactly what Contacts does
        // when you type one in yourself.
        table["father"] = CNLabelContactRelationFather
        table["mother"] = CNLabelContactRelationMother
        table["parent"] = CNLabelContactRelationParent
        table["brother"] = CNLabelContactRelationBrother
        table["sister"] = CNLabelContactRelationSister
        table["child"] = CNLabelContactRelationChild
        table["friend"] = CNLabelContactRelationFriend
        table["spouse"] = CNLabelContactRelationSpouse
        table["partner"] = CNLabelContactRelationPartner
        table["assistant"] = CNLabelContactRelationAssistant
        table["manager"] = CNLabelContactRelationManager
        return table
    }

    /// `_$!<Mobile>!$_` becomes `mobile`; a custom label is returned as typed.
    ///
    /// The framework's own `localizedString(forLabel:)` answers in the user's
    /// language, which is right for a screen and wrong for a CSV column or a
    /// command-line argument that has to mean the same thing everywhere. This
    /// unwraps the delimiters instead and lowercases what is inside.
    public static func readable(_ rawLabel: String) -> String {
        guard rawLabel.hasPrefix("_$!<"), rawLabel.hasSuffix(">!$_") else {
            return rawLabel
        }
        return String(rawLabel.dropFirst(4).dropLast(4)).lowercased()
    }

    /// `mobile` becomes `_$!<Mobile>!$_`; an unknown word is kept as a custom
    /// label, which the framework supports and Contacts shows verbatim.
    public static func raw(_ word: String) -> String {
        let key = word.lowercased().filter { $0.isLetter || $0.isNumber }
        return known[key] ?? word
    }
}
