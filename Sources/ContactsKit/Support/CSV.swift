//
//  CSV.swift
//  ContactsKit
//
//  Created by David Sherlock on 2026.
//
//  RFC 4180, so the library stands on its own.
//
//  There is a CSV writer in the command-line kit already, and the `contacts`
//  tool uses it. This exists for the other caller: an iOS app has no command
//  line and cannot take that dependency, and "export my contacts" is the first
//  thing such an app does. Thirty lines here is a better answer than an app
//  pasting its own — which is how the app this was measured against ended up
//  writing `"\(givenName),\(familyName),…"` with no quoting at all, so that a
//  contact called `Smith, Jr` shifted every column after it.
//
//  Both implementations are checked against the same RFC vectors, so they
//  cannot drift apart into two dialects.
//

import Foundation

/// Writes and reads comma-separated values.
public enum CSV {

    /// A header row and a row per record, CRLF-terminated as the RFC says.
    public static func write(columns: [String], rows: [[String]]) -> String {
        var out = columns.map(field).joined(separator: ",") + "\r\n"
        for row in rows {
            // Squared against the header, so a short row cannot shift a
            // neighbour's values into the wrong column.
            let cells = columns.indices.map { $0 < row.count ? row[$0] : "" }
            out += cells.map(field).joined(separator: ",") + "\r\n"
        }
        return out
    }

    /// One cell, quoted when it has to be and defused when it would execute.
    static func field(_ value: String) -> String {
        let defused = defuse(value)
        guard defused.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return defused }
        return "\"" + defused.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Stops a spreadsheet executing a cell.
    ///
    /// A leading `=`, `+`, `@`, `-` or tab makes Excel and Numbers evaluate
    /// the cell rather than show it, and contact data is full of values people
    /// typed. A leading apostrophe forces text; a plain number is left alone
    /// so numeric columns still import as numbers.
    static func defuse(_ value: String) -> String {
        guard let first = value.first,
              first == "=" || first == "+" || first == "@" || first == "-" || first == "\t",
              Double(value) == nil
        else { return value }
        return "'" + value
    }

    /// Reads a CSV document into rows, honouring quotes and embedded newlines.
    ///
    /// Written as a scanner rather than `split(separator:)`, which cannot see
    /// that a comma inside quotes is not a separator — the mistake that makes
    /// half the CSV readers in the world lose a column the first time somebody's
    /// job title contains one.
    ///
    /// **Over unicode scalars, not characters.** Swift counts `\r\n` as a
    /// single `Character` — one grapheme cluster — so comparing a `Character`
    /// to `"\r"` matches nothing in a CRLF document, and every row of an
    /// RFC 4180 file (which mandates CRLF) runs into the next. Measured: the
    /// first version of this read a two-row document as one row whose second
    /// cell was `Company\r\nSmith, Jr`.
    public static func read(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false

        let scalars = Array(text.unicodeScalars)
        var index = 0

        func endCell() { row.append(cell); cell = "" }
        func endRow() {
            endCell()
            // A trailing line break must not produce a final empty row.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            index += 1

            if quoted {
                if scalar == "\"" {
                    // A doubled quote is a literal one.
                    if index < scalars.count, scalars[index] == "\"" {
                        cell.unicodeScalars.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    cell.unicodeScalars.append(scalar)
                }
                continue
            }

            switch scalar {
            case "\"": quoted = true
            case ",": endCell()
            case "\r":
                // Swallow the paired newline of a CRLF.
                if index < scalars.count, scalars[index] == "\n" { index += 1 }
                endRow()
            case "\n": endRow()
            default: cell.unicodeScalars.append(scalar)
            }
        }
        if !cell.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
