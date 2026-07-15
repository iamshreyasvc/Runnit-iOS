//
//  Continents.swift
//  Runnit iOS
//
//  Maps ISO 3166-1 alpha-2 country codes to continents, so the Passport can
//  show "world coverage" — how much of the planet a traveler has touched.
//

import Foundation

enum Continent: String, CaseIterable, Identifiable, Hashable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    case northAmerica = "North America"
    case southAmerica = "South America"
    case oceania = "Oceania"
    case antarctica = "Antarctica"

    var id: String { rawValue }

    /// A representative emoji for the continent, used on coverage chips.
    var emoji: String {
        switch self {
        case .africa:       return "🌍"
        case .asia:         return "🌏"
        case .europe:       return "🌍"
        case .northAmerica: return "🌎"
        case .southAmerica: return "🌎"
        case .oceania:      return "🌏"
        case .antarctica:   return "🧊"
        }
    }

    /// The continent a country belongs to, or nil for an unknown code.
    static func of(isoCode: String) -> Continent? {
        Self.byCode[isoCode.uppercased()]
    }

    /// Total number of continents (excluding Antarctica, which is a novelty and
    /// distorts a "% of the world" figure most travelers will never complete).
    static var inhabitedCount: Int { 6 }

    private static let byCode: [String: Continent] = {
        var map: [String: Continent] = [:]
        func add(_ codes: String, _ continent: Continent) {
            for code in codes.split(separator: " ") { map[String(code)] = continent }
        }
        add("DZ AO BJ BW BF BI CM CV CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU YT MA MZ NA NE NG RE RW SH ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW", .africa)
        add("AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KW KG LA LB MO MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE", .asia)
        add("AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG HU IS IE IM IT JE LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SJ SE CH UA GB VA AX", .europe)
        add("AI AG AW BS BB BZ BM VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI", .northAmerica)
        add("AR BO BR CL CO EC FK GF GY PY PE SR UY VE", .southAmerica)
        add("AS AU CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV VU WF", .oceania)
        add("AQ BV GS TF HM", .antarctica)
        return map
    }()
}
