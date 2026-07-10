// Fetches TD Journey Time Indicators v2 XML and maps the configured
// slot pairs into protocol entries. Note: the feed uses a default XML
// namespace; XMLParser (namespaces off) reports plain element names.
import Foundation

final class JourneyTimeService: NSObject {
    static let url = URL(string: "https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml")!

    struct Record {
        var location = ""
        var destination = ""
        var journeyType = ""
        var journeyData = ""
        var colourID = ""
        var captureDate = ""
    }

    private var records: [Record] = []
    private var current: Record?
    private var currentElement = ""
    private var currentText = ""

    func fetch() async throws -> (captureEpoch: UInt32, entries: [DashProtocol.JourneyEntry]) {
        var req = URLRequest(url: Self.url)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return parse(data)
    }

    func parse(_ data: Data) -> (captureEpoch: UInt32, entries: [DashProtocol.JourneyEntry]) {
        records = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        var byPair: [String: Record] = [:]
        var captureEpoch = UInt32(Date().timeIntervalSince1970)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        df.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        for r in records {
            byPair["\(r.location)|\(r.destination)"] = r
            if let d = df.date(from: r.captureDate) {
                captureEpoch = UInt32(d.timeIntervalSince1970)
            }
        }

        let entries = SlotConfig.journeySlots().map { slot -> DashProtocol.JourneyEntry in
            guard let r = byPair["\(slot.location)|\(slot.destination)"] else {
                return .init(slot: slot.slot, minutes: DashProtocol.minutesNA, colour: 0)
            }
            let colour = UInt8(r.colourID).flatMap { (1...3).contains($0) ? $0 : nil } ?? 0
            if r.journeyType == "1", let mins = Int(r.journeyData), mins >= 0 {
                return .init(slot: slot.slot, minutes: UInt8(min(mins, 250)), colour: colour)
            }
            if r.journeyType == "2", r.journeyData == "1" {
                return .init(slot: slot.slot, minutes: DashProtocol.minutesCongestion, colour: colour)
            }
            if r.journeyType == "2", r.journeyData == "3" {
                return .init(slot: slot.slot, minutes: DashProtocol.minutesClosed, colour: colour)
            }
            return .init(slot: slot.slot, minutes: DashProtocol.minutesNA, colour: 0)
        }
        return (captureEpoch, entries)
    }
}

extension JourneyTimeService: XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if elementName == "jtis_journey_time" { current = Record() }
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "LOCATION_ID": current?.location = text
        case "DESTINATION_ID": current?.destination = text
        case "JOURNEY_TYPE": current?.journeyType = text
        case "JOURNEY_DATA": current?.journeyData = text
        case "COLOUR_ID": current?.colourID = text
        case "CAPTURE_DATE": current?.captureDate = text
        case "jtis_journey_time":
            if let r = current { records.append(r) }
            current = nil
        default: break
        }
    }
}
