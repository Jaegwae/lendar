import Foundation

/// Parsed subset of a CalDAV `<response>` element.
///
/// CalDAV servers use XML namespaces inconsistently, so the parser stores only the
/// local element names this app needs: hrefs, display names, calendar-data payloads,
/// component names, and resource-type flags.
struct CalDAVXMLResponse: Equatable {
    var hrefs: [String] = []
    var currentUserPrincipalHrefs: [String] = []
    var calendarHomeSetHrefs: [String] = []
    var calendarDataValues: [String] = []
    var displayName: String?
    var contentType: String?
    var componentNames: Set<String> = []
    var isCalendar = false
    var isCollection = false
}

/// XMLParser-backed extraction helpers for CalDAV server responses.
///
/// Earlier versions used namespace-tolerant regexes. This parser keeps the same
/// tolerance by looking at XML local names, while avoiding fragile "response block"
/// substring parsing for nested CalDAV payloads.
enum CalDAVXML {
    static func responses(from xml: String) -> [CalDAVXMLResponse] {
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        let delegate = CalDAVXMLParserDelegate()
        parser.delegate = delegate
        return parser.parse() ? delegate.responses : []
    }

    static func firstCurrentUserPrincipalHref(from xml: String) -> String? {
        responses(from: xml).flatMap(\.currentUserPrincipalHrefs).first
    }

    static func firstCalendarHomeSetHref(from xml: String) -> String? {
        responses(from: xml).flatMap(\.calendarHomeSetHrefs).first
    }

    static func extractCalendarData(from xml: String) -> [String] {
        responses(from: xml)
            .flatMap(\.calendarDataValues)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private final class CalDAVXMLParserDelegate: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var currentResponse: CalDAVXMLResponse?
    private var textBuffer = ""

    private var currentElement: String {
        elementStack.last ?? ""
    }

    private var isInsideCurrentUserPrincipal: Bool {
        elementStack.contains("current-user-principal")
    }

    private var isInsideCalendarHomeSet: Bool {
        elementStack.contains("calendar-home-set")
    }

    private var isInsideResponse: Bool {
        currentResponse != nil
    }

    private(set) var responses: [CalDAVXMLResponse] = []

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        elementStack.append(name)
        textBuffer = ""

        if name == "response" {
            currentResponse = CalDAVXMLResponse()
        }

        if isInsideResponse {
            if name == "calendar" {
                currentResponse?.isCalendar = true
            }
            if name == "collection" {
                currentResponse?.isCollection = true
            }
            if name == "comp", let component = attributeDict.first(where: { localName($0.key) == "name" })?.value {
                currentResponse?.componentNames.insert(component.uppercased())
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        textBuffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let name = localName(elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInsideResponse, !value.isEmpty {
            capture(value: value, for: name)
        }

        if name == "response", let response = currentResponse {
            responses.append(response)
            currentResponse = nil
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        textBuffer = ""
    }

    private func capture(value: String, for name: String) {
        switch name {
        case "href":
            if isInsideCurrentUserPrincipal {
                currentResponse?.currentUserPrincipalHrefs.append(value)
            } else if isInsideCalendarHomeSet {
                currentResponse?.calendarHomeSetHrefs.append(value)
            } else {
                currentResponse?.hrefs.append(value)
            }
        case "calendar-data":
            currentResponse?.calendarDataValues.append(value)
        case "displayname":
            currentResponse?.displayName = value
        case "getcontenttype":
            currentResponse?.contentType = value
        default:
            break
        }
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }
}
