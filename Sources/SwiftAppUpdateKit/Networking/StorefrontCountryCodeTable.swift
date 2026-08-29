//
//  StorefrontCountryCodeTable.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

/// Maps every three-letter ISO 3166-1 alpha-3 storefront code Apple operates
/// to its two-letter ISO 3166-1 alpha-2 equivalent.
///
/// StoreKit's `Storefront.countryCode` uses alpha-3, while the Lookup API
/// expects alpha-2. The table is complete rather than trimmed: an unlisted
/// code falls through to the device-region proxy, producing region-specific
/// defects that are invisible during testing and hard to reproduce.
enum StorefrontCountryCodeTable {
    static func countryCode(forThreeLetterStorefrontCode threeLetterCode: String) -> String? {
        return self.table[threeLetterCode]
    }

    private static let table: [String: String] = [
        // A
        "AFG": "AF",  // Afghanistan
        "AGO": "AO",  // Angola
        "AIA": "AI",  // Anguilla
        "ALB": "AL",  // Albania
        "AND": "AD",  // Andorra
        "ARE": "AE",  // United Arab Emirates
        "ARG": "AR",  // Argentina
        "ARM": "AM",  // Armenia
        "ATG": "AG",  // Antigua and Barbuda
        "AUS": "AU",  // Australia
        "AUT": "AT",  // Austria
        "AZE": "AZ",  // Azerbaijan
        // B
        "BDI": "BI",  // Burundi
        "BEL": "BE",  // Belgium
        "BEN": "BJ",  // Benin
        "BFA": "BF",  // Burkina Faso
        "BGD": "BD",  // Bangladesh
        "BGR": "BG",  // Bulgaria
        "BHR": "BH",  // Bahrain
        "BHS": "BS",  // Bahamas
        "BIH": "BA",  // Bosnia and Herzegovina
        "BLR": "BY",  // Belarus
        "BLZ": "BZ",  // Belize
        "BMU": "BM",  // Bermuda
        "BOL": "BO",  // Bolivia
        "BRA": "BR",  // Brazil
        "BRB": "BB",  // Barbados
        "BRN": "BN",  // Brunei
        "BTN": "BT",  // Bhutan
        "BWA": "BW",  // Botswana
        // C
        "CAF": "CF",  // Central African Republic
        "CAN": "CA",  // Canada
        "CHE": "CH",  // Switzerland
        "CHL": "CL",  // Chile
        "CHN": "CN",  // China
        "CIV": "CI",  // Côte d'Ivoire
        "CMR": "CM",  // Cameroon
        "COD": "CD",  // Democratic Republic of the Congo
        "COG": "CG",  // Republic of the Congo
        "COK": "CK",  // Cook Islands
        "COL": "CO",  // Colombia
        "CPV": "CV",  // Cabo Verde
        "CRI": "CR",  // Costa Rica
        "CYM": "KY",  // Cayman Islands
        "CYP": "CY",  // Cyprus
        "CZE": "CZ",  // Czech Republic
        // D
        "DEU": "DE",  // Germany
        "DJI": "DJ",  // Djibouti
        "DMA": "DM",  // Dominica
        "DNK": "DK",  // Denmark
        "DOM": "DO",  // Dominican Republic
        "DZA": "DZ",  // Algeria
        // E
        "ECU": "EC",  // Ecuador
        "EGY": "EG",  // Egypt
        "ERI": "ER",  // Eritrea
        "ESP": "ES",  // Spain
        "EST": "EE",  // Estonia
        "ETH": "ET",  // Ethiopia
        // F
        "FIN": "FI",  // Finland
        "FJI": "FJ",  // Fiji
        "FRA": "FR",  // France
        "FSM": "FM",  // Micronesia
        // G
        "GAB": "GA",  // Gabon
        "GBR": "GB",  // United Kingdom
        "GEO": "GE",  // Georgia
        "GHA": "GH",  // Ghana
        "GIN": "GN",  // Guinea
        "GMB": "GM",  // Gambia
        "GNB": "GW",  // Guinea-Bissau
        "GNQ": "GQ",  // Equatorial Guinea
        "GRC": "GR",  // Greece
        "GRD": "GD",  // Grenada
        "GTM": "GT",  // Guatemala
        "GUY": "GY",  // Guyana
        // H
        "HKG": "HK",  // Hong Kong
        "HND": "HN",  // Honduras
        "HRV": "HR",  // Croatia
        "HTI": "HT",  // Haiti
        "HUN": "HU",  // Hungary
        // I
        "IDN": "ID",  // Indonesia
        "IND": "IN",  // India
        "IRL": "IE",  // Ireland
        "IRQ": "IQ",  // Iraq
        "ISL": "IS",  // Iceland
        "ISR": "IL",  // Israel
        "ITA": "IT",  // Italy
        // J
        "JAM": "JM",  // Jamaica
        "JOR": "JO",  // Jordan
        "JPN": "JP",  // Japan
        // K
        "KAZ": "KZ",  // Kazakhstan
        "KEN": "KE",  // Kenya
        "KGZ": "KG",  // Kyrgyzstan
        "KHM": "KH",  // Cambodia
        "KNA": "KN",  // Saint Kitts and Nevis
        "KOR": "KR",  // South Korea
        "KWT": "KW",  // Kuwait
        // L
        "LAO": "LA",  // Laos
        "LBN": "LB",  // Lebanon
        "LBR": "LR",  // Liberia
        "LBY": "LY",  // Libya
        "LCA": "LC",  // Saint Lucia
        "LKA": "LK",  // Sri Lanka
        "LSO": "LS",  // Lesotho
        "LTU": "LT",  // Lithuania
        "LUX": "LU",  // Luxembourg
        "LVA": "LV",  // Latvia
        // M
        "MAC": "MO",  // Macao
        "MAR": "MA",  // Morocco
        "MDA": "MD",  // Moldova
        "MDG": "MG",  // Madagascar
        "MDV": "MV",  // Maldives
        "MEX": "MX",  // Mexico
        "MKD": "MK",  // North Macedonia
        "MLI": "ML",  // Mali
        "MLT": "MT",  // Malta
        "MMR": "MM",  // Myanmar
        "MNE": "ME",  // Montenegro
        "MNG": "MN",  // Mongolia
        "MOZ": "MZ",  // Mozambique
        "MRT": "MR",  // Mauritania
        "MSR": "MS",  // Montserrat
        "MUS": "MU",  // Mauritius
        "MWI": "MW",  // Malawi
        "MYS": "MY",  // Malaysia
        // N
        "NAM": "NA",  // Namibia
        "NER": "NE",  // Niger
        "NGA": "NG",  // Nigeria
        "NIC": "NI",  // Nicaragua
        "NLD": "NL",  // Netherlands
        "NOR": "NO",  // Norway
        "NPL": "NP",  // Nepal
        "NRU": "NR",  // Nauru
        "NZL": "NZ",  // New Zealand
        // O
        "OMN": "OM",  // Oman
        // P
        "PAK": "PK",  // Pakistan
        "PAN": "PA",  // Panama
        "PER": "PE",  // Peru
        "PHL": "PH",  // Philippines
        "PLW": "PW",  // Palau
        "PNG": "PG",  // Papua New Guinea
        "POL": "PL",  // Poland
        "PRT": "PT",  // Portugal
        "PRY": "PY",  // Paraguay
        // Q
        "QAT": "QA",  // Qatar
        // R
        "ROU": "RO",  // Romania
        "RUS": "RU",  // Russia
        "RWA": "RW",  // Rwanda
        // S
        "SAU": "SA",  // Saudi Arabia
        "SDN": "SD",  // Sudan
        "SEN": "SN",  // Senegal
        "SGP": "SG",  // Singapore
        "SLB": "SB",  // Solomon Islands
        "SLE": "SL",  // Sierra Leone
        "SLV": "SV",  // El Salvador
        "SOM": "SO",  // Somalia
        "SRB": "RS",  // Serbia
        "SSD": "SS",  // South Sudan
        "STP": "ST",  // São Tomé and Príncipe
        "SUR": "SR",  // Suriname
        "SVK": "SK",  // Slovakia
        "SVN": "SI",  // Slovenia
        "SWE": "SE",  // Sweden
        "SWZ": "SZ",  // Eswatini
        "SYC": "SC",  // Seychelles
        // T
        "TCA": "TC",  // Turks and Caicos Islands
        "TCD": "TD",  // Chad
        "TGO": "TG",  // Togo
        "THA": "TH",  // Thailand
        "TJK": "TJ",  // Tajikistan
        "TKM": "TM",  // Turkmenistan
        "TLS": "TL",  // Timor-Leste
        "TON": "TO",  // Tonga
        "TTO": "TT",  // Trinidad and Tobago
        "TUN": "TN",  // Tunisia
        "TUR": "TR",  // Turkey
        "TUV": "TV",  // Tuvalu
        "TWN": "TW",  // Taiwan
        "TZA": "TZ",  // Tanzania
        // U
        "UGA": "UG",  // Uganda
        "UKR": "UA",  // Ukraine
        "URY": "UY",  // Uruguay
        "USA": "US",  // United States
        "UZB": "UZ",  // Uzbekistan
        // V
        "VCT": "VC",  // Saint Vincent and the Grenadines
        "VEN": "VE",  // Venezuela
        "VGB": "VG",  // British Virgin Islands
        "VNM": "VN",  // Vietnam
        "VUT": "VU",  // Vanuatu
        // W
        "WSM": "WS",  // Samoa
        // X
        "XKX": "XK",  // Kosovo (de facto standard, no official ISO 3166-1 code)
        // Y
        "YEM": "YE",  // Yemen
        // Z
        "ZAF": "ZA",  // South Africa
        "ZMB": "ZM",  // Zambia
        "ZWE": "ZW",  // Zimbabwe
    ]
}
