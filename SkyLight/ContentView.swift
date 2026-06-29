import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject private var model: SkyLightModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    SkyDialView(day: model.day, now: model.currentDate)
                        .frame(minHeight: 430)
                    CurrentPhaseCard(day: model.day, now: model.currentDate)
                    EventGrid(day: model.day)
                    summaryTools
                    disclaimer
                }
                .padding(24)
            }
            .background(LinearGradient(colors: [.black, Color(red: 0.05, green: 0.08, blue: 0.14)], startPoint: .top, endPoint: .bottom))
        }
        .navigationTitle("SkyLight")
        .preferredColorScheme(.dark)
        .onReceive(model.timer) { date in
            model.currentDate = date
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedLocationID) {
            Section("Location") {
                TextField("Name", text: $model.location.name)
                LabeledContent("Latitude") {
                    TextField("Latitude", value: $model.location.latitude, format: .number.precision(.fractionLength(4)))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Longitude") {
                    TextField("Longitude", value: $model.location.longitude, format: .number.precision(.fractionLength(4)))
                        .multilineTextAlignment(.trailing)
                }
                TextField("Timezone", text: $model.location.timeZoneIdentifier)
                DatePicker("Date", selection: $model.selectedDate, displayedComponents: .date)
                Button("Save Favourite") {
                    model.saveFavourite()
                }
            }

            Section("Favourites") {
                ForEach(model.favourites) { favourite in
                    Button(favourite.name) {
                        model.location = favourite
                        model.selectedLocationID = favourite.id
                    }
                }
                .onDelete(perform: model.deleteFavourite)
            }

            Section("Creator") {
                Text("Created by FPV-dB")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 250)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SkyLight")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text("Daylight and twilight planner for aviation, drone pilots, photographers, astronomers, hikers and outdoor users.")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack {
                Label(model.day.currentPhase(at: model.currentDate).name, systemImage: model.menuSymbol)
                Text("Next: \(model.day.nextEvent(after: model.currentDate)?.name ?? "No event")")
                Text(model.countdownText)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTools: some View {
        HStack {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.dailySummary, forType: .string)
            } label: {
                Label("Copy Daily Summary", systemImage: "doc.on.doc")
            }
            Spacer()
            Button {
                Task { await model.scheduleNotifications() }
            } label: {
                Label("Schedule Solar Notifications", systemImage: "bell.badge")
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private var disclaimer: some View {
        Text("SkyLight is for planning assistance only. Always check official aviation rules, NOTAMs, local restrictions, permissions and actual conditions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SkyDialView: View {
    let day: SolarDay
    let now: Date

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(day.segments) { segment in
                    DialSegment(start: day.fraction(segment.start), end: day.fraction(segment.end))
                        .stroke(style: StrokeStyle(lineWidth: 34, lineCap: .butt))
                        .foregroundStyle(segment.phase.color)
                        .frame(width: size * 0.72, height: size * 0.72)
                }

                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: size * 0.82, height: size * 0.82)

                ForEach(["N", "E", "S", "W"], id: \.self) { label in
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .offset(labelOffset(label, radius: size * 0.43))
                }

                currentIndicator(size: size)

                VStack(spacing: 6) {
                    Text("You are here")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(day.currentPhase(at: now).name)
                        .font(.title.bold())
                    Text(day.nextEvent(after: now).map { "Next: \($0.name)" } ?? "No upcoming event")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 28))
    }

    private func currentIndicator(size: CGFloat) -> some View {
        let angle = Angle.degrees(day.fraction(now) * 360 - 90)
        return Rectangle()
            .fill(.cyan)
            .frame(width: 3, height: size * 0.39)
            .offset(y: -size * 0.195)
            .rotationEffect(angle)
            .shadow(color: .cyan.opacity(0.9), radius: 8)
    }

    private func labelOffset(_ label: String, radius: CGFloat) -> CGSize {
        switch label {
        case "N": return CGSize(width: 0, height: -radius)
        case "E": return CGSize(width: radius, height: 0)
        case "S": return CGSize(width: 0, height: radius)
        default: return CGSize(width: -radius, height: 0)
        }
    }
}

struct DialSegment: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(start * 360 - 90),
            endAngle: .degrees(end * 360 - 90),
            clockwise: false
        )
        return path
    }
}

struct CurrentPhaseCard: View {
    let day: SolarDay
    let now: Date

    var body: some View {
        let phase = day.currentPhase(at: now)
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Phase")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(phase.name)
                .font(.largeTitle.bold())
                .foregroundStyle(phase.color)
            Text(day.nextEvent(after: now).map { "Countdown to \($0.name): \(Self.relative($0.date, from: now))" } ?? "No next event for this date.")
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(phase.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
    }

    static func relative(_ date: Date, from now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}

struct EventGrid: View {
    let day: SolarDay

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            ForEach(day.cards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(card.value)
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var model: SkyLightModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.day.currentPhase(at: model.currentDate).name, systemImage: model.menuSymbol)
                .font(.headline)
            Text(model.day.nextEvent(after: model.currentDate).map { "Next: \($0.name)" } ?? "No next event")
            Text(model.countdownText)
                .foregroundStyle(.secondary)
            Divider()
            Button("Open SkyLight") { NSApp.activate(ignoringOtherApps: true) }
            Button("Refresh") { model.currentDate = Date() }
            Button("Settings") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 260)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: SkyLightModel

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            Toggle("24-hour clock", isOn: $model.use24HourClock)
            Toggle("Show seconds", isOn: $model.showSeconds)
            Toggle("Notification sound", isOn: $model.notificationSound)
            Toggle("Automatic location", isOn: $model.automaticLocation)
            TextField("Timezone override", text: $model.timezoneOverride)
            Picker("Notification lead time", selection: $model.notificationLeadMinutes) {
                ForEach([0, 5, 10, 15, 30, 60], id: \.self) { minutes in
                    Text(minutes == 0 ? "At event time" : "\(minutes) minutes before").tag(minutes)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

final class SkyLightModel: ObservableObject {
    @Published var location = SkyLocation.defaultAdelaide { didSet { saveLocation() } }
    @Published var selectedDate = Date()
    @Published var currentDate = Date()
    @Published var selectedLocationID: UUID?
    @Published var favourites: [SkyLocation] = SkyLocation.loadFavourites()
    @AppStorage("launchAtLogin") var launchAtLogin = false { didSet { updateLoginItem() } }
    @AppStorage("use24HourClock") var use24HourClock = true
    @AppStorage("showSeconds") var showSeconds = false
    @AppStorage("notificationSound") var notificationSound = true
    @AppStorage("automaticLocation") var automaticLocation = false
    @AppStorage("timezoneOverride") var timezoneOverride = "Australia/Adelaide"
    @AppStorage("notificationLeadMinutes") var notificationLeadMinutes = 15

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init() {
        location = SkyLocation.loadCurrent()
    }

    var day: SolarDay {
        SolarCalculator.day(for: selectedDate, location: location)
    }

    var menuSymbol: String {
        switch day.currentPhase(at: currentDate) {
        case .daylight, .goldenHour: return "sun.max.fill"
        case .civilTwilight, .blueHour: return currentDate < (day.sunrise ?? currentDate) ? "sunrise.fill" : "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    var countdownText: String {
        guard let next = day.nextEvent(after: currentDate) else { return "No upcoming event" }
        return CurrentPhaseCard.relative(next.date, from: currentDate)
    }

    var dailySummary: String {
        ([location.name, location.coordinateText, "Timezone: \(location.timeZoneIdentifier)"] + day.cards.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
    }

    func saveFavourite() {
        if !favourites.contains(where: { $0.name == location.name }) {
            favourites.append(location)
            SkyLocation.saveFavourites(favourites)
        }
    }

    func deleteFavourite(at offsets: IndexSet) {
        favourites.remove(atOffsets: offsets)
        SkyLocation.saveFavourites(favourites)
    }

    func scheduleNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: day.events.map { "skylight-\($0.name)" })
        for event in day.events {
            let fireDate = event.date.addingTimeInterval(Double(-notificationLeadMinutes * 60))
            guard fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = event.name
            content.body = notificationLeadMinutes == 0 ? "Solar event now at \(location.name)." : "\(notificationLeadMinutes) minutes until \(event.name) at \(location.name)."
            if notificationSound { content.sound = .default }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "skylight-\(event.name)", content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func saveLocation() {
        SkyLocation.saveCurrent(location)
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

struct SkyLocation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String

    static let defaultAdelaide = SkyLocation(name: "Adelaide", latitude: -34.9285, longitude: 138.6007, timeZoneIdentifier: "Australia/Adelaide")
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Australia/Adelaide")! }
    var coordinateText: String { String(format: "%.4f, %.4f", latitude, longitude) }

    static func loadCurrent() -> SkyLocation {
        guard let data = UserDefaults.standard.data(forKey: "currentLocation"),
              let location = try? JSONDecoder().decode(SkyLocation.self, from: data) else { return defaultAdelaide }
        return location
    }

    static func saveCurrent(_ location: SkyLocation) {
        UserDefaults.standard.set(try? JSONEncoder().encode(location), forKey: "currentLocation")
    }

    static func loadFavourites() -> [SkyLocation] {
        guard let data = UserDefaults.standard.data(forKey: "favourites"),
              let locations = try? JSONDecoder().decode([SkyLocation].self, from: data) else { return [defaultAdelaide] }
        return locations
    }

    static func saveFavourites(_ locations: [SkyLocation]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(locations), forKey: "favourites")
    }
}

enum SkyPhase: String, CaseIterable {
    case astronomicalNight, astronomicalTwilight, nauticalTwilight, civilTwilight, blueHour, goldenHour, daylight

    var name: String {
        switch self {
        case .astronomicalNight: return "Astronomical Night"
        case .astronomicalTwilight: return "Astronomical Twilight"
        case .nauticalTwilight: return "Nautical Twilight"
        case .civilTwilight: return "Civil Twilight"
        case .blueHour: return "Blue Hour"
        case .goldenHour: return "Golden Hour"
        case .daylight: return "Daylight"
        }
    }

    var color: Color {
        switch self {
        case .astronomicalNight: return Color(red: 0.02, green: 0.03, blue: 0.11)
        case .astronomicalTwilight: return Color.indigo
        case .nauticalTwilight: return Color.blue
        case .civilTwilight: return Color.cyan
        case .blueHour: return Color(red: 0.22, green: 0.44, blue: 0.95)
        case .goldenHour: return Color.orange
        case .daylight: return Color.yellow
        }
    }
}

struct SolarEvent: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
}

struct SolarSegment: Identifiable {
    let id = UUID()
    let phase: SkyPhase
    let start: Date
    let end: Date
}

struct SolarCard: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

struct SolarDay {
    let location: SkyLocation
    let date: Date
    let startOfDay: Date
    let endOfDay: Date
    let events: [SolarEvent]
    let segments: [SolarSegment]
    let sunrise: Date?
    let sunset: Date?

    var cards: [SolarCard] {
        let formatter = Self.timeFormatter(location.timeZone)
        func time(_ date: Date?) -> String { date.map { formatter.string(from: $0) } ?? "Not occurring" }
        let civilDawn = event("Civil Dawn")
        let civilDusk = event("Civil Dusk")
        let nauticalDawn = event("Nautical Dawn")
        let nauticalDusk = event("Nautical Dusk")
        let astronomicalDawn = event("Astronomical Dawn")
        let astronomicalDusk = event("Astronomical Dusk")
        return [
            SolarCard(name: "Sunrise", value: time(sunrise)),
            SolarCard(name: "Sunset", value: time(sunset)),
            SolarCard(name: "Civil Dawn", value: time(civilDawn)),
            SolarCard(name: "Civil Dusk", value: time(civilDusk)),
            SolarCard(name: "Nautical Dawn", value: time(nauticalDawn)),
            SolarCard(name: "Nautical Dusk", value: time(nauticalDusk)),
            SolarCard(name: "Astronomical Dawn", value: time(astronomicalDawn)),
            SolarCard(name: "Astronomical Dusk", value: time(astronomicalDusk)),
            SolarCard(name: "Solar Noon", value: time(event("Solar Noon"))),
            SolarCard(name: "Solar Midnight", value: time(event("Solar Midnight"))),
            SolarCard(name: "Golden Hour Morning", value: range(sunrise, sunrise?.addingTimeInterval(3600))),
            SolarCard(name: "Golden Hour Evening", value: range(sunset?.addingTimeInterval(-3600), sunset)),
            SolarCard(name: "Blue Hour Morning", value: range(civilDawn, sunrise)),
            SolarCard(name: "Blue Hour Evening", value: range(sunset, civilDusk)),
            SolarCard(name: "Day Length", value: duration(sunrise, sunset)),
            SolarCard(name: "Civil Day Length", value: duration(civilDawn, civilDusk)),
            SolarCard(name: "Night Length", value: duration(astronomicalDusk, astronomicalDawn?.addingTimeInterval(24 * 3600)))
        ]
    }

    func currentPhase(at moment: Date) -> SkyPhase {
        segments.first(where: { moment >= $0.start && moment < $0.end })?.phase ?? .astronomicalNight
    }

    func nextEvent(after moment: Date) -> SolarEvent? {
        events.sorted { $0.date < $1.date }.first { $0.date > moment }
    }

    func fraction(_ moment: Date) -> Double {
        min(1, max(0, moment.timeIntervalSince(startOfDay) / 86_400))
    }

    private func event(_ name: String) -> Date? {
        events.first { $0.name == name }?.date
    }

    private func range(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end, end > start else { return "Not occurring" }
        let formatter = Self.timeFormatter(location.timeZone)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func duration(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "Not available" }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func timeFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

enum SolarCalculator {
    static func day(for date: Date, location: SkyLocation) -> SolarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let sunrise = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 90.833, rising: true)
        let sunset = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 90.833, rising: false)
        let civilDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 96, rising: true)
        let civilDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 96, rising: false)
        let nauticalDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 102, rising: true)
        let nauticalDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 102, rising: false)
        let astroDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 108, rising: true)
        let astroDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, zenith: 108, rising: false)
        let noon = solarNoon(longitude: location.longitude, date: start)
        let midnight = noon.addingTimeInterval(12 * 3600)

        var events = [
            ("Astronomical Dawn", astroDawn), ("Nautical Dawn", nauticalDawn), ("Civil Dawn", civilDawn),
            ("Sunrise", sunrise), ("Solar Noon", noon), ("Sunset", sunset),
            ("Civil Dusk", civilDusk), ("Nautical Dusk", nauticalDusk), ("Astronomical Dusk", astroDusk),
            ("Solar Midnight", midnight)
        ].compactMap { name, date in date.map { SolarEvent(name: name, date: $0) } }

        var segments: [SolarSegment] = []
        func add(_ phase: SkyPhase, _ from: Date?, _ to: Date?) {
            guard let from, let to, to > from else { return }
            segments.append(SolarSegment(phase: phase, start: from, end: to))
        }

        add(.astronomicalNight, start, astroDawn)
        add(.astronomicalTwilight, astroDawn, nauticalDawn)
        add(.nauticalTwilight, nauticalDawn, civilDawn)
        add(.civilTwilight, civilDawn, sunrise)
        add(.blueHour, civilDawn, sunrise)
        add(.goldenHour, sunrise, sunrise?.addingTimeInterval(3600))
        add(.daylight, sunrise?.addingTimeInterval(3600), sunset?.addingTimeInterval(-3600))
        add(.goldenHour, sunset?.addingTimeInterval(-3600), sunset)
        add(.blueHour, sunset, civilDusk)
        add(.civilTwilight, sunset, civilDusk)
        add(.nauticalTwilight, civilDusk, nauticalDusk)
        add(.astronomicalTwilight, nauticalDusk, astroDusk)
        add(.astronomicalNight, astroDusk, end)

        if segments.isEmpty {
            segments = [SolarSegment(phase: .astronomicalNight, start: start, end: end)]
        }

        events.sort { $0.date < $1.date }
        return SolarDay(location: location, date: date, startOfDay: start, endOfDay: end, events: events, segments: segments, sunrise: sunrise, sunset: sunset)
    }

    private static func solarEvent(latitude: Double, longitude: Double, date: Date, zenith: Double, rising: Bool) -> Date? {
        let day = dayOfYear(date)
        let lngHour = longitude / 15
        let t = Double(day) + (((rising ? 6.0 : 18.0) - lngHour) / 24)
        let meanAnomaly = (0.9856 * t) - 3.289
        var trueLongitude = meanAnomaly + (1.916 * sin(deg(meanAnomaly))) + (0.020 * sin(deg(2 * meanAnomaly))) + 282.634
        trueLongitude = normalize(trueLongitude)
        var rightAscension = rad(atan(0.91764 * tan(deg(trueLongitude))))
        rightAscension = normalize(rightAscension)
        rightAscension += floor(trueLongitude / 90) * 90 - floor(rightAscension / 90) * 90
        rightAscension /= 15
        let sinDeclination = 0.39782 * sin(deg(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHourAngle = (cos(deg(zenith)) - (sinDeclination * sin(deg(latitude)))) / (cosDeclination * cos(deg(latitude)))
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        var hourAngle = rising ? 360 - rad(acos(cosHourAngle)) : rad(acos(cosHourAngle))
        hourAngle /= 15
        let localMeanTime = hourAngle + rightAscension - (0.06571 * t) - 6.622
        let utcHour = normalizeHour(localMeanTime - lngHour)
        return date.addingTimeInterval(utcHour * 3600)
    }

    private static func solarNoon(longitude: Double, date: Date) -> Date {
        date.addingTimeInterval((12 - longitude / 15) * 3600)
    }

    private static func dayOfYear(_ date: Date) -> Int {
        Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private static func deg(_ value: Double) -> Double { value * .pi / 180 }
    private static func rad(_ value: Double) -> Double { value * 180 / .pi }
    private static func normalize(_ value: Double) -> Double { value.truncatingRemainder(dividingBy: 360) + (value < 0 ? 360 : 0) }
    private static func normalizeHour(_ value: Double) -> Double { value.truncatingRemainder(dividingBy: 24) + (value < 0 ? 24 : 0) }
}
