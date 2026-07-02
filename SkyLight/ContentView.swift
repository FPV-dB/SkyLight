import AppKit
import Combine
import CoreLocation
import MapKit
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
                    SkyDialView(day: model.day, now: model.displayDate)
                        .frame(minHeight: 430)
                    DaySimulatorView(model: model)
                    CurrentStatusCard(model: model)
                    EventTimelineView(model: model)
                    PlanningDashboard(model: model)
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
        .background(MenuBarWindowController())
        .onReceive(model.timer) { date in
            model.tick(date)
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedLocationID) {
            Section("Location") {
                Button {
                    model.useCurrentLocation()
                } label: {
                    Label("Use Current Location", systemImage: "location.fill")
                }

                HStack {
                    TextField("Search city", text: $model.citySearchText)
                    Button {
                        model.searchCity()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Search city")
                }

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
                HStack {
                    Button {
                        model.previousDay()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    DatePicker("Date", selection: $model.selectedDate, displayedComponents: .date)
                    Button {
                        model.nextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                Button {
                    model.jumpToToday()
                } label: {
                    Label("Today", systemImage: "calendar")
                }
                LocationMapView(model: model)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack {
                    Button("Save Favourite") {
                        model.saveFavourite()
                    }
                    Button("Rename") {
                        model.renameSelectedFavourite()
                    }
                }
            }

            Section("Favourites") {
                ForEach(model.favourites) { favourite in
                    Button(favourite.displayPath) {
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
        HStack(alignment: .top, spacing: 18) {
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

            Spacer(minLength: 0)

            TimezoneClockView(
                date: model.currentDate,
                location: model.location,
                use24HourClock: model.use24HourClock,
                showSeconds: model.showSeconds
            )
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

struct TimezoneClockView: View {
    let date: Date
    let location: SkyLocation
    let use24HourClock: Bool
    let showSeconds: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Label(location.name, systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(timeString(in: location.timeZone))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(location.timeZoneIdentifier)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if location.timeZone.identifier != TimeZone.current.identifier {
                Text("Mac: \(timeString(in: .current)) \(TimeZone.current.identifier)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(minWidth: 220, alignment: .trailing)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .help("SkyLight calculations and dial labels are using \(location.timeZoneIdentifier).")
    }

    private func timeString(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if use24HourClock {
            formatter.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            formatter.dateFormat = showSeconds ? "h:mm:ss a" : "h:mm a"
        }
        return formatter.string(from: date)
    }
}

struct SkyDialView: View {
    let day: SolarDay
    let now: Date
    @State private var hoveredSegmentID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(day.segments) { segment in
                    DialSegment(start: day.fraction(segment.start), end: day.fraction(segment.end))
                        .stroke(style: StrokeStyle(lineWidth: 34, lineCap: .butt))
                        .foregroundStyle(segment.phase.color)
                        .frame(width: size * 0.72, height: size * 0.72)
                        .help(segment.tooltip(timeZone: day.location.timeZone))
                        .onHover { isHovering in
                            hoveredSegmentID = isHovering ? segment.id : (hoveredSegmentID == segment.id ? nil : hoveredSegmentID)
                        }
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

                ForEach(labelledSegments) { segment in
                    Text(segment.phase.shortName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 72)
                        .offset(phaseLabelOffset(for: segment, radius: size * 0.49))
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

                if let hoveredSegment {
                    DialHoverInfo(segment: hoveredSegment, timeZone: day.location.timeZone)
                        .frame(width: min(260, size * 0.5))
                        .offset(y: -size * 0.37)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: hoveredSegmentID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 28))
    }

    private var hoveredSegment: SolarSegment? {
        day.segments.first { $0.id == hoveredSegmentID }
    }

    private var labelledSegments: [SolarSegment] {
        var seenPhases = Set<SkyPhase>()
        return day.segments.filter { segment in
            guard segment.duration >= 30 * 60 else { return false }
            guard !seenPhases.contains(segment.phase) else { return false }
            seenPhases.insert(segment.phase)
            return true
        }
    }

    private func currentIndicator(size: CGFloat) -> some View {
        let angle = Angle.degrees(day.fraction(now) * 360)
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

    private func phaseLabelOffset(for segment: SolarSegment, radius: CGFloat) -> CGSize {
        let middle = (day.fraction(segment.start) + day.fraction(segment.end)) / 2
        let radians = (middle * 360 - 90) * .pi / 180
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}

private struct DialHoverInfo: View {
    let segment: SolarSegment
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(segment.phase.color)
                    .frame(width: 9, height: 9)
                Text(segment.phase.name)
                    .font(.headline)
            }
            Label(timeRange, systemImage: "clock")
            Label(segment.phase.approximateColorTemperature, systemImage: "thermometer.medium")
        }
        .font(.callout)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var timeRange: String {
        let formatter = SolarDay.timeFormatter(timeZone)
        return "\(formatter.string(from: segment.start)) - \(formatter.string(from: segment.end))"
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(day.cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(card.value)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct DaySimulatorView: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Day Simulator", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text(model.simulatorTimeText)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            Slider(value: Binding(
                get: { model.simulatorMinute },
                set: { model.setSimulatorMinute($0) }
            ), in: 0...1439, step: 1) {
                Text("Time")
            }
            HStack {
                Text("00:00")
                Spacer()
                Toggle("Live", isOn: $model.isLiveMode)
                    .toggleStyle(.switch)
                Spacer()
                Text("23:59")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(model.displayPhase.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: model.displayPhase)
    }
}

struct CurrentStatusCard: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        let sun = model.sunPosition
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Status", systemImage: model.menuSymbol)
                    .font(.headline)
                Spacer()
                Text(model.displayClockText)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                MetricTile(title: "Current", value: model.displayPhase.name, color: model.displayPhase.color)
                MetricTile(title: "Next", value: model.nextEventText, color: .cyan)
                MetricTile(title: "Elevation", value: String(format: "%.1f°", sun.elevation), color: sun.elevation >= 0 ? .yellow : .indigo)
                MetricTile(title: "Azimuth", value: String(format: "%.0f°", sun.azimuth), color: .blue)
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EventTimelineView: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Event Timeline", systemImage: "list.bullet.rectangle")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(model.timelineEvents) { event in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(event.phase.color)
                            .frame(width: 9, height: 9)
                        Text(event.timeText)
                            .font(.callout.monospacedDigit())
                            .frame(width: 54, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.callout.weight(.semibold))
                            Text(event.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(event.countdownText(from: model.displayDate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(event.date > model.displayDate ? .cyan : .secondary)
                    }
                    .padding(.vertical, 7)
                    .help(event.helpText)
                    Divider().opacity(0.45)
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PlanningDashboard: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
            FlightPlanningPanel(model: model)
            SunInformationPanel(model: model)
            MoonInformationPanel(model: model)
            WeatherPlaceholderPanel()
        }
    }
}

struct FlightPlanningPanel: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Flight Planning", systemImage: "airplane")
                .font(.headline)
            MetricLine("Legal daylight remaining", model.remainingText(until: model.day.sunset))
            MetricLine("Minutes until sunset", model.minutesText(until: model.day.sunset))
            MetricLine("Golden hour remaining", model.remainingForPhase(.goldenHour))
            MetricLine("Civil twilight remaining", model.remainingForPhase(.civilTwilight))
            MetricLine("Daylight percentage", "\(Int(model.daylightPercentage * 100))%")
            MetricLine("Total daylight", model.day.durationText(model.day.sunrise, model.day.sunset))
            MetricLine("Total night", model.day.durationText(model.day.event("Astronomical Dusk"), model.day.event("Astronomical Dawn")?.addingTimeInterval(86_400)))
        }
        .plannerPanel()
    }
}

struct SunInformationPanel: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        let sun = model.sunPosition
        VStack(alignment: .leading, spacing: 10) {
            Label("Sun", systemImage: "sun.max.fill")
                .font(.headline)
            MetricLine("Elevation", String(format: "%.1f°", sun.elevation))
            MetricLine("Azimuth", String(format: "%.0f°", sun.azimuth))
            MetricLine("Maximum elevation", String(format: "%.1f°", model.maximumSolarElevation))
            MetricLine("Solar noon", model.day.timeText(model.day.event("Solar Noon")))
            SunPathMiniView(progress: model.day.fraction(model.displayDate), elevation: sun.elevation)
                .frame(height: 70)
        }
        .plannerPanel()
    }
}

struct MoonInformationPanel: View {
    @ObservedObject var model: SkyLightModel

    var body: some View {
        let moon = model.moonInfo
        VStack(alignment: .leading, spacing: 10) {
            Label("Moon", systemImage: "moon.fill")
                .font(.headline)
            HStack(spacing: 14) {
                MoonGraphic(illumination: moon.illumination)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading) {
                    Text(moon.phaseName)
                        .font(.callout.weight(.semibold))
                    Text("\(Int(moon.illumination * 100))% illuminated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            MetricLine("Moonrise", moon.moonrise)
            MetricLine("Moonset", moon.moonset)
            MetricLine("Altitude", moon.altitude)
            MetricLine("Azimuth", moon.azimuth)
        }
        .plannerPanel()
    }
}

struct WeatherPlaceholderPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weather", systemImage: "cloud.sun")
                .font(.headline)
            MetricLine("Wind", "Optional")
            MetricLine("Temperature", "Optional")
            MetricLine("Visibility", "Optional")
            MetricLine("Cloud cover", "Optional")
            Text("Ready for a weather provider without slowing solar calculations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .plannerPanel()
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MetricLine: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
        }
        .font(.callout)
    }
}

struct SunPathMiniView: View {
    let progress: Double
    let elevation: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let x = width * progress
            let normalized = min(1, max(0, (elevation + 18) / 90))
            let y = height - height * normalized
            Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.78))
                path.addQuadCurve(to: CGPoint(x: width, y: height * 0.78), control: CGPoint(x: width / 2, y: height * 0.05))
            }
            .stroke(.yellow.opacity(0.7), lineWidth: 2)
            Circle()
                .fill(.yellow)
                .frame(width: 10, height: 10)
                .position(x: x, y: y)
        }
    }
}

struct MoonGraphic: View {
    let illumination: Double

    var body: some View {
        ZStack {
            Circle().fill(.gray.opacity(0.28))
            Circle()
                .trim(from: 0, to: max(0.05, min(1, illumination)))
                .rotation(.degrees(-90))
                .fill(.white.opacity(0.88))
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

struct LocationMapView: View {
    @ObservedObject var model: SkyLightModel
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: SkyLocation.defaultAdelaide.latitude, longitude: SkyLocation.defaultAdelaide.longitude),
        span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 18)
    ))

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                Marker(model.location.name, coordinate: model.location.coordinate)
            }
            .mapStyle(.imagery(elevation: .realistic))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                model.setCoordinate(coordinate)
            }
            .onAppear {
                camera = .region(MKCoordinateRegion(center: model.location.coordinate, span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)))
            }
            .onChange(of: model.location.coordinateText) { _, _ in
                camera = .region(MKCoordinateRegion(center: model.location.coordinate, span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)))
            }
        }
    }
}

extension View {
    func plannerPanel() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
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
            Button("Open SkyLight") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Refresh") { model.refreshNow() }
            SettingsLink {
                Text("Settings")
            }
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
            Toggle("Automatic location", isOn: Binding(
                get: { model.automaticLocation },
                set: { model.setAutomaticLocation($0) }
            ))
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

struct MenuBarWindowController: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configure(window: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?

        func configure(window: NSWindow?) {
            guard let window, window !== self.window else { return }
            self.window = window
            window.delegate = self
            window.standardWindowButton(.miniaturizeButton)?.target = self
            window.standardWindowButton(.miniaturizeButton)?.action = #selector(hideToMenuBar)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }

        @objc private func hideToMenuBar() {
            window?.orderOut(nil)
        }
    }
}

final class SkyLightModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location = SkyLocation.defaultAdelaide { didSet { saveLocation() } }
    @Published var selectedDate = Date()
    @Published var currentDate = Date()
    @Published var selectedLocationID: UUID?
    @Published var favourites: [SkyLocation] = SkyLocation.loadFavourites()
    @Published var citySearchText = ""
    @Published var simulatorMinute = 0.0
    @Published var isLiveMode = true
    @AppStorage("launchAtLogin") var launchAtLogin = false { didSet { updateLoginItem() } }
    @AppStorage("use24HourClock") var use24HourClock = true
    @AppStorage("showSeconds") var showSeconds = false
    @AppStorage("notificationSound") var notificationSound = true
    @AppStorage("automaticLocation") var automaticLocation = false
    @AppStorage("timezoneOverride") var timezoneOverride = "Australia/Adelaide"
    @AppStorage("notificationLeadMinutes") var notificationLeadMinutes = 15

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        location = SkyLocation.loadCurrent()
        if automaticLocation {
            requestAutomaticLocation()
        }
    }

    var day: SolarDay {
        SolarCalculator.day(for: selectedDate, location: location)
    }

    var displayDate: Date {
        isLiveMode ? currentDate : day.startOfDay.addingTimeInterval(simulatorMinute * 60)
    }

    var displayPhase: SkyPhase {
        day.currentPhase(at: displayDate)
    }

    var simulatorTimeText: String {
        day.timeText(displayDate)
    }

    var displayClockText: String {
        day.timeText(displayDate)
    }

    var sunPosition: SunPosition {
        SolarCalculator.sunPosition(at: displayDate, location: location)
    }

    var nextEventText: String {
        guard let next = day.nextEvent(after: displayDate) else { return "No event" }
        return "\(next.name) in \(CurrentPhaseCard.relative(next.date, from: displayDate))"
    }

    var timelineEvents: [TimelineEvent] {
        day.timelineEvents(relativeTo: displayDate)
    }

    var maximumSolarElevation: Double {
        SolarCalculator.sunPosition(at: day.event("Solar Noon") ?? displayDate, location: location).elevation
    }

    var daylightPercentage: Double {
        guard let sunrise = day.sunrise, let sunset = day.sunset, sunset > sunrise else { return 0 }
        return min(1, max(0, displayDate.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)))
    }

    var moonInfo: MoonInfo {
        MoonCalculator.info(for: displayDate, day: day)
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

    func tick(_ date: Date) {
        let wasTrackingToday = Calendar.current.isDate(selectedDate, inSameDayAs: currentDate)
        currentDate = date
        if isLiveMode {
            simulatorMinute = minutesSinceStartOfDay(date)
        }
        if wasTrackingToday {
            selectedDate = date
        }
    }

    func refreshNow() {
        tick(Date())
        if automaticLocation {
            requestAutomaticLocation()
        }
    }

    func setAutomaticLocation(_ enabled: Bool) {
        automaticLocation = enabled
        if enabled {
            requestAutomaticLocation()
        }
    }

    func useCurrentLocation() {
        automaticLocation = true
        requestAutomaticLocation()
    }

    func searchCity() {
        let query = citySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        geocoder.geocodeAddressString(query) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self, let placemark = placemarks?.first, let coordinate = placemark.location?.coordinate else { return }
                self.applyCoordinate(
                    coordinate,
                    name: [placemark.locality, placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", "),
                    timeZone: placemark.timeZone
                )
            }
        }
    }

    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let placemark = placemarks?.first
                let name = [placemark?.locality, placemark?.administrativeArea, placemark?.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                self.applyCoordinate(coordinate, name: name.isEmpty ? "Map Location" : name, timeZone: placemark?.timeZone)
            }
        }
    }

    func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate.addingTimeInterval(-86_400)
    }

    func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate.addingTimeInterval(86_400)
    }

    func jumpToToday() {
        isLiveMode = true
        tick(Date())
    }

    func setSimulatorMinute(_ minute: Double) {
        isLiveMode = false
        simulatorMinute = minute
    }

    func saveFavourite() {
        if !favourites.contains(where: { $0.name == location.name }) {
            favourites.append(location)
            SkyLocation.saveFavourites(favourites)
        }
    }

    func renameSelectedFavourite() {
        guard let selectedLocationID,
              let index = favourites.firstIndex(where: { $0.id == selectedLocationID }) else { return }
        favourites[index].name = location.name
        favourites[index].notes = location.notes
        SkyLocation.saveFavourites(favourites)
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

    private func requestAutomaticLocation() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if automaticLocation {
            requestAutomaticLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard automaticLocation, let latest = locations.last else { return }
        updateLocation(from: latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }

    private func updateLocation(from coreLocation: CLLocation) {
        geocoder.reverseGeocodeLocation(coreLocation) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let placemark = placemarks?.first
                let name = [placemark?.locality, placemark?.administrativeArea, placemark?.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                let timeZoneIdentifier = placemark?.timeZone?.identifier ?? TimeZone.current.identifier
                self.location = SkyLocation(
                    name: name.isEmpty ? "Current Location" : name,
                    latitude: coreLocation.coordinate.latitude,
                    longitude: coreLocation.coordinate.longitude,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                self.timezoneOverride = timeZoneIdentifier
            }
        }
    }

    private func applyCoordinate(_ coordinate: CLLocationCoordinate2D, name: String, timeZone: TimeZone?) {
        let timeZoneIdentifier = timeZone?.identifier ?? TimeZone.current.identifier
        location = SkyLocation(
            name: name.isEmpty ? "Selected Location" : name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZoneIdentifier
        )
        timezoneOverride = timeZoneIdentifier
    }

    private func minutesSinceStartOfDay(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    func remainingText(until date: Date?) -> String {
        guard let date, date > displayDate else { return "0m" }
        return CurrentPhaseCard.relative(date, from: displayDate)
    }

    func minutesText(until date: Date?) -> String {
        guard let date, date > displayDate else { return "0 min" }
        return "\(Int(date.timeIntervalSince(displayDate) / 60)) min"
    }

    func remainingForPhase(_ phase: SkyPhase) -> String {
        guard let segment = day.segments.first(where: { $0.phase == phase && displayDate >= $0.start && displayDate < $0.end }) else {
            return "0m"
        }
        return CurrentPhaseCard.relative(segment.end, from: displayDate)
    }
}

struct SkyLocation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var elevationMeters: Double?
    var notes = ""
    var folder = ""

    static let defaultAdelaide = SkyLocation(name: "Adelaide", latitude: -34.9285, longitude: 138.6007, timeZoneIdentifier: "Australia/Adelaide")
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "Australia/Adelaide")! }
    var coordinateText: String { String(format: "%.4f, %.4f", latitude, longitude) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var displayPath: String { folder.isEmpty ? name : "\(folder) / \(name)" }

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

    var shortName: String {
        switch self {
        case .astronomicalNight: return "Night"
        case .astronomicalTwilight: return "Astro"
        case .nauticalTwilight: return "Nautical"
        case .civilTwilight: return "Civil"
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

    var approximateColorTemperature: String {
        switch self {
        case .astronomicalNight: return "below 2,000 K"
        case .astronomicalTwilight: return "2,000-4,000 K"
        case .nauticalTwilight: return "4,000-7,000 K"
        case .civilTwilight: return "7,000-10,000 K"
        case .blueHour: return "9,000-12,000 K"
        case .goldenHour: return "2,000-3,500 K"
        case .daylight: return "5,500-6,500 K"
        }
    }

    var eventSummary: String {
        switch self {
        case .astronomicalNight: return "Dark sky conditions"
        case .astronomicalTwilight: return "Faint sky glow"
        case .nauticalTwilight: return "Horizon still visible"
        case .civilTwilight: return "Usable outdoor light"
        case .blueHour: return "Cool blue ambient light"
        case .goldenHour: return "Warm low-angle sunlight"
        case .daylight: return "Full daylight"
        }
    }

    var explanation: String {
        switch self {
        case .astronomicalNight:
            return "The sun is more than 18 degrees below the horizon. Useful for astronomy and dark-sky planning."
        case .astronomicalTwilight:
            return "The sun is between 12 and 18 degrees below the horizon. Astronomers watch this boundary closely."
        case .nauticalTwilight:
            return "The sun is between 6 and 12 degrees below the horizon. The horizon may remain distinguishable."
        case .civilTwilight:
            return "The sun is between 0 and 6 degrees below the horizon. Many outdoor activities remain practical."
        case .blueHour:
            return "A short cool-light period near sunrise or sunset. Useful for cityscapes and landscape photography."
        case .goldenHour:
            return "Low-angle sunlight with warm color and long shadows. Popular for photography and visual flight planning."
        case .daylight:
            return "The sun is above the horizon. Useful for daylight operations, route planning and outdoor activity timing."
        }
    }
}

struct SolarEvent: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    let phase: SkyPhase
    let timeText: String
    let explanation: String
    let helpText: String

    func countdownText(from date: Date) -> String {
        guard self.date > date else { return "passed" }
        return CurrentPhaseCard.relative(self.date, from: date)
    }
}

struct SunPosition {
    let elevation: Double
    let azimuth: Double
}

struct MoonInfo {
    let phaseName: String
    let illumination: Double
    let moonrise: String
    let moonset: String
    let altitude: String
    let azimuth: String
}

struct SolarSegment: Identifiable {
    let id = UUID()
    let phase: SkyPhase
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    func tooltip(timeZone: TimeZone) -> String {
        let formatter = SolarDay.timeFormatter(timeZone)
        return "\(phase.name) \(formatter.string(from: start))-\(formatter.string(from: end)); approx. \(phase.approximateColorTemperature)"
    }
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

    func event(_ name: String) -> Date? {
        events.first { $0.name == name }?.date
    }

    func timeText(_ date: Date?) -> String {
        guard let date else { return "Not occurring" }
        return Self.timeFormatter(location.timeZone).string(from: date)
    }

    func durationText(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return "Not available" }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    func timelineEvents(relativeTo date: Date) -> [TimelineEvent] {
        let formatter = Self.timeFormatter(location.timeZone)
        return events.map { event in
            let phase = phaseForEvent(event.name)
            return TimelineEvent(
                name: event.name,
                date: event.date,
                phase: phase,
                timeText: formatter.string(from: event.date),
                explanation: phase.eventSummary,
                helpText: phase.explanation
            )
        }
    }

    private func phaseForEvent(_ name: String) -> SkyPhase {
        if name.contains("Astronomical") { return .astronomicalTwilight }
        if name.contains("Nautical") { return .nauticalTwilight }
        if name.contains("Civil") { return .civilTwilight }
        if name == "Sunrise" || name == "Sunset" { return .goldenHour }
        if name.contains("Noon") { return .daylight }
        return .astronomicalNight
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
        let sunrise = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 90.833, rising: true)
        let sunset = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 90.833, rising: false)
        let civilDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 96, rising: true)
        let civilDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 96, rising: false)
        let nauticalDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 102, rising: true)
        let nauticalDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 102, rising: false)
        let astroDawn = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 108, rising: true)
        let astroDusk = solarEvent(latitude: location.latitude, longitude: location.longitude, date: start, timeZone: location.timeZone, zenith: 108, rising: false)
        let noon = solarNoon(longitude: location.longitude, date: start, timeZone: location.timeZone)
        let midnight = calendar.date(byAdding: .hour, value: 12, to: noon) ?? noon.addingTimeInterval(12 * 3600)

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

    private static func solarEvent(latitude: Double, longitude: Double, date: Date, timeZone: TimeZone, zenith: Double, rising: Bool) -> Date? {
        let day = dayOfYear(date, timeZone: timeZone)
        let localStart = localStartOfDay(for: date, timeZone: timeZone)
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
        let localOffsetHours = Double(timeZone.secondsFromGMT(for: localStart)) / 3600
        let localHour = normalizeHour(utcHour + localOffsetHours)
        return localStart.addingTimeInterval(localHour * 3600)
    }

    private static func solarNoon(longitude: Double, date: Date, timeZone: TimeZone) -> Date {
        let day = Double(dayOfYear(date, timeZone: timeZone))
        let gamma = 2 * Double.pi / 365 * (day - 1)
        let equationOfTime = 229.18 * (
            0.000075 +
            0.001868 * cos(gamma) -
            0.032077 * sin(gamma) -
            0.014615 * cos(2 * gamma) -
            0.040849 * sin(2 * gamma)
        )
        let utcMinutes = 720 - (4 * longitude) - equationOfTime
        let localStart = localStartOfDay(for: date, timeZone: timeZone)
        let localOffsetMinutes = Double(timeZone.secondsFromGMT(for: localStart)) / 60
        let localMinutes = normalizeMinutes(utcMinutes + localOffsetMinutes)
        return localStart.addingTimeInterval(localMinutes * 60)
    }

    static func sunPosition(at date: Date, location: SkyLocation) -> SunPosition {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let day = Double(dayOfYear(date, timeZone: location.timeZone))
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60 + Double(components.second ?? 0) / 3600
        let gamma = 2 * Double.pi / 365 * (day - 1 + (hour - 12) / 24)
        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)
        let equationOfTime = 229.18 * (
            0.000075 +
            0.001868 * cos(gamma) -
            0.032077 * sin(gamma) -
            0.014615 * cos(2 * gamma) -
            0.040849 * sin(2 * gamma)
        )
        let offsetMinutes = Double(location.timeZone.secondsFromGMT(for: date)) / 60
        let trueSolarMinutes = hour * 60 + equationOfTime + 4 * location.longitude - offsetMinutes
        let hourAngle = deg(trueSolarMinutes / 4 - 180)
        let latitude = deg(location.latitude)
        let elevation = rad(asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)))
        let azimuthRadians = atan2(sin(hourAngle), cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude))
        let azimuth = normalize(rad(azimuthRadians) + 180)
        return SunPosition(elevation: elevation, azimuth: azimuth)
    }

    private static func dayOfYear(_ date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private static func localStartOfDay(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    private static func deg(_ value: Double) -> Double { value * .pi / 180 }
    private static func rad(_ value: Double) -> Double { value * 180 / .pi }
    private static func normalize(_ value: Double) -> Double { value.truncatingRemainder(dividingBy: 360) + (value < 0 ? 360 : 0) }
    private static func normalizeHour(_ value: Double) -> Double { value.truncatingRemainder(dividingBy: 24) + (value < 0 ? 24 : 0) }
    private static func normalizeMinutes(_ value: Double) -> Double { value.truncatingRemainder(dividingBy: 1_440) + (value < 0 ? 1_440 : 0) }
}

enum MoonCalculator {
    static func info(for date: Date, day: SolarDay) -> MoonInfo {
        let phase = moonPhase(for: date)
        let illumination = 0.5 * (1 - cos(2 * Double.pi * phase))
        let age = phase * 29.530588853
        let phaseName: String
        switch age {
        case 0..<1.84566, 27.68493...29.53059: phaseName = "New Moon"
        case 1.84566..<5.53699: phaseName = "Waxing Crescent"
        case 5.53699..<9.22831: phaseName = "First Quarter"
        case 9.22831..<12.91963: phaseName = "Waxing Gibbous"
        case 12.91963..<16.61096: phaseName = "Full Moon"
        case 16.61096..<20.30228: phaseName = "Waning Gibbous"
        case 20.30228..<23.99361: phaseName = "Last Quarter"
        default: phaseName = "Waning Crescent"
        }

        let moonrise = day.sunrise?.addingTimeInterval(age / 29.530588853 * 86_400)
        let moonset = moonrise?.addingTimeInterval(12.4 * 3_600)
        let formatter = SolarDay.timeFormatter(day.location.timeZone)
        let altitude = sin(2 * Double.pi * day.fraction(date) + phase * 2 * Double.pi) * 55
        let azimuth = (day.fraction(date) * 360 + phase * 360).truncatingRemainder(dividingBy: 360)
        return MoonInfo(
            phaseName: phaseName,
            illumination: illumination,
            moonrise: moonrise.map { formatter.string(from: $0) } ?? "Approx. unavailable",
            moonset: moonset.map { formatter.string(from: $0) } ?? "Approx. unavailable",
            altitude: String(format: "%.1f°", altitude),
            azimuth: String(format: "%.0f°", azimuth)
        )
    }

    private static func moonPhase(for date: Date) -> Double {
        let reference = Date(timeIntervalSince1970: 947_182_440) // 2000-01-06 18:14 UTC, near new moon.
        let days = date.timeIntervalSince(reference) / 86_400
        let phase = days.truncatingRemainder(dividingBy: 29.530588853) / 29.530588853
        return phase < 0 ? phase + 1 : phase
    }
}
