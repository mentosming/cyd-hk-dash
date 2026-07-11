// 咪錶地圖 — HK Lands Department basemap (CSDI XYZ tiles) with a pin per metered
// parking space, coloured by live occupancy.
//
// Two design constraints drive this file:
//  • 20k+ spaces: only the ones inside the visible rect are turned into
//    annotations, and MapKit's native clustering collapses them when zoomed out.
//  • Occupancy is a ~700 KB CSV: fetched once, cached, refreshed on demand /
//    every 60 s while the tab is visible — never per-pin.
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Tile overlays (Lands Department, via CSDI)

enum HKBasemap {
    // Verified live: standard web-mercator XYZ, no API key, zoom 10–20.
    static let basemapURL = "https://mapapi.geodata.gov.hk/gs/api/v1.0.0/xyz/basemap/WGS84/{z}/{x}/{y}.png"
    static let labelURL = "https://mapapi.geodata.gov.hk/gs/api/v1.0.0/xyz/label/hk/tc/WGS84/{z}/{x}/{y}.png"

    static func overlays() -> [MKTileOverlay] {
        let base = MKTileOverlay(urlTemplate: basemapURL)
        base.canReplaceMapContent = true          // hide Apple's basemap underneath
        base.minimumZ = 10
        base.maximumZ = 20

        let label = MKTileOverlay(urlTemplate: labelURL)
        label.canReplaceMapContent = false        // transparent street-name layer
        label.minimumZ = 10
        label.maximumZ = 20

        return [base, label]
    }
}

// MARK: - Annotation

final class MeterAnnotation: NSObject, MKAnnotation {
    let space: MeterStore.Space
    var occupancy: MeterQueryService.Occupancy?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: space.lat, longitude: space.lon)
    }
    var title: String? { space.street }
    var subtitle: String? {
        guard let o = occupancy else { return "冇即時資料" }
        if !o.working { return "暫停使用" }
        return (o.vacant ? "有空位" : "已被使用") + " · 最長泊 \(space.lpp) 分鐘"
    }

    enum State { case vacant, occupied, unknown }
    var state: State {
        guard let o = occupancy, o.working else { return .unknown }
        return o.vacant ? .vacant : .occupied
    }

    init(space: MeterStore.Space) { self.space = space }
}

// MARK: - Screen

struct MeterMapScreen: View {
    @EnvironmentObject var coordinator: DashCoordinator
    @StateObject private var model = MeterMapModel()
    // @AppStorage (not DemoMode.isEnabled directly) so SwiftUI actually observes
    // the flip and we can re-source the occupancy snapshot.
    @AppStorage(DemoMode.key) private var demoEnabled = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MeterMapView(model: model, store: coordinator.meterStore)
                    .ignoresSafeArea(edges: .top)

                // Lands Department attribution — required by the CSDI map API terms
                HStack {
                    Text("© 地圖資料由地政總署提供")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                    legend
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .overlay(alignment: .topTrailing) { statusPill.padding(12) }
            .overlay(alignment: .center) {
                if model.tooZoomedOut {
                    Label("放大睇咪錶", systemImage: "plus.magnifyingglass")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.black.opacity(0.65), in: Capsule())
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.tooZoomedOut)
            .navigationTitle("咪錶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshOccupancy(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .task {
                // The restructure dropped the old ContentView.onAppear that asked
                // for this — without it the map never shows the user's location
                // and the 掃一掃 meter flow silently fails.
                coordinator.meterQuery.requestPermissions()

                await coordinator.meterStore.loadOrRefresh()
                model.storeReady = coordinator.meterStore.count > 0
                // Populate unconditionally: demo mode can be switched on later.
                model.allSpaceIDs = coordinator.meterStore.allIDs
                await model.refreshOccupancy(force: true)

                // Keep occupancy fresh while the tab is on screen (the TD feed
                // updates about every minute).
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled { break }
                    await model.refreshOccupancy(force: true)
                }
            }
            .onChange(of: demoEnabled) { _, _ in
                Task { await model.refreshOccupancy(force: true) }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach([("有空位", Brand.green), ("已泊", Brand.red), ("暫停", Color.gray)], id: \.0) { l in
                HStack(spacing: 3) {
                    Circle().fill(l.1).frame(width: 7, height: 7)
                    Text(l.0).font(.system(size: 10)).foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    @ViewBuilder private var statusPill: some View {
        if model.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.white)
                Text("更新緊…").font(.caption2).foregroundStyle(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
        } else if let at = model.occupancyAt {
            Text(WidgetFormat.ageText(at))
                .font(.caption2).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
        }
    }
}

// MARK: - Model

@MainActor
final class MeterMapModel: ObservableObject {
    @Published var occupancy: [String: MeterQueryService.Occupancy] = [:]
    @Published var occupancyAt: Date?
    @Published var isLoading = false
    @Published var storeReady = false
    @Published var tooZoomedOut = false
    /// Bumped whenever occupancy changes so the map view re-colours its pins.
    @Published var occupancyRevision = 0

    /// Set by the view once the space DB is loaded — demo mode needs the ids.
    var allSpaceIDs: [String] = []

    func refreshOccupancy(force: Bool = false) async {
        if !force, let at = occupancyAt, -at.timeIntervalSinceNow < 60 { return }
        isLoading = true
        defer { isLoading = false }

        if DemoMode.isEnabled {
            occupancy = DemoMode.occupancySnapshot(for: allSpaceIDs)
            occupancyAt = Date()
            occupancyRevision += 1
            return
        }
        if let occ = await MeterQueryService.fetchOccupancy() {
            occupancy = occ
            occupancyAt = Date()
            occupancyRevision += 1
        }
    }
}

// MARK: - MKMapView bridge

struct MeterMapView: UIViewRepresentable {
    /// Above this visible width we stop materialising pins — 20k annotations
    /// would be both useless and unusably slow. Measured in metres so it is
    /// independent of the screen's aspect ratio.
    static let maxVisibleWidthM: CLLocationDistance = 6_000

    @ObservedObject var model: MeterMapModel
    let store: MeterStore

    func makeCoordinator() -> Coord { Coord(model: model, store: store) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .light   // the gov basemap is a light design

        for o in HKBasemap.overlays() { map.addOverlay(o, level: .aboveRoads) }

        map.register(MeterPinView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        map.register(MeterClusterView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)

        // Default: Victoria Harbour. Sized in METRES, not degrees — a square
        // degree span on a 2:1 portrait screen gets expanded by MapKit to a
        // latitudeDelta far bigger than asked, which used to push the initial
        // view past the "too zoomed out" gate so no pins ever appeared.
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.2975, longitude: 114.1722),
            latitudinalMeters: MeterMapView.maxVisibleWidthM * 0.6,
            longitudinalMeters: MeterMapView.maxVisibleWidthM * 0.6), animated: false)

        context.coordinator.locationManager.requestWhenInUseAuthorization()
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.applyOccupancyIfChanged()
        context.coordinator.reloadIfStoreBecameReady()
    }

    final class Coord: NSObject, MKMapViewDelegate {
        let model: MeterMapModel
        let store: MeterStore
        let locationManager = CLLocationManager()
        weak var map: MKMapView?

        private var shownIDs = Set<String>()
        private var lastRevision = -1
        private var didInitialLoad = false

        init(model: MeterMapModel, store: MeterStore) {
            self.model = model
            self.store = store
        }

        // Government XYZ tiles
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            syncAnnotations(in: mapView)
        }

        func reloadIfStoreBecameReady() {
            guard !didInitialLoad, model.storeReady, let map else { return }
            didInitialLoad = true
            syncAnnotations(in: map)
        }

        /// Only materialise the spaces inside the visible rect; drop the rest.
        /// Zoomed out past `maxVisibleWidthM` we show none (and the UI says so),
        /// because 20k annotations are neither useful nor fast.
        private func syncAnnotations(in map: MKMapView) {
            guard store.count > 0 else { return }
            let region = map.region

            let widthM = map.visibleMapRect.width
                * MKMetersPerMapPointAtLatitude(region.center.latitude)
            let tooWide = !widthM.isFinite || widthM > MeterMapView.maxVisibleWidthM
            if model.tooZoomedOut != tooWide { model.tooZoomedOut = tooWide }

            guard !tooWide else {
                if !shownIDs.isEmpty {
                    map.removeAnnotations(map.annotations.compactMap { $0 as? MeterAnnotation })
                    shownIDs.removeAll()
                }
                return
            }

            let visible = store.spaces(inRegion: region)
            let visibleIDs = Set(visible.map(\.id))

            let stale = map.annotations.compactMap { $0 as? MeterAnnotation }
                .filter { !visibleIDs.contains($0.space.id) }
            if !stale.isEmpty { map.removeAnnotations(stale) }

            let toAdd = visible.filter { !shownIDs.contains($0.id) }
            let anns = toAdd.map { space -> MeterAnnotation in
                let a = MeterAnnotation(space: space)
                a.occupancy = model.occupancy[space.id]
                return a
            }
            if !anns.isEmpty { map.addAnnotations(anns) }

            shownIDs = visibleIDs
        }

        /// Re-colour existing pins when a new occupancy snapshot lands.
        func applyOccupancyIfChanged() {
            guard model.occupancyRevision != lastRevision, let map else { return }
            lastRevision = model.occupancyRevision
            for case let a as MeterAnnotation in map.annotations {
                a.occupancy = model.occupancy[a.space.id]
                if let v = map.view(for: a) as? MeterPinView { v.apply(a) }
            }
            // Clustered members have no view of their own (map.view(for:) is nil),
            // and MKClusterAnnotation doesn't re-run didSet when its members
            // mutate — so the bubble's vacant count would stay stale. Refresh
            // the cluster views explicitly.
            for case let c as MKClusterAnnotation in map.annotations {
                (map.view(for: c) as? MeterClusterView)?.refresh()
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let m = annotation as? MeterAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                for: m) as! MeterPinView
            v.apply(m)
            return v
        }
    }
}

// MARK: - Pin views

final class MeterPinView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "meter"
        canShowCallout = true
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        layer.cornerRadius = 7
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        displayPriority = .defaultLow
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(_ m: MeterAnnotation) {
        annotation = m
        clusteringIdentifier = "meter"
        backgroundColor = Self.colour(for: m.state)
    }

    static func colour(for s: MeterAnnotation.State) -> UIColor {
        switch s {
        case .vacant: return UIColor(Brand.green)
        case .occupied: return UIColor(Brand.red)
        case .unknown: return .systemGray
        }
    }
}

/// Cluster bubble: shows the vacant count, and goes green as soon as one space
/// inside it is free — that is the only number a driver cares about.
final class MeterClusterView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        layer.cornerRadius = 17
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        collisionMode = .circle

        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.frame = bounds
        addSubview(label)
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet { refresh() }
    }

    /// Also called from the map coordinator when a new occupancy snapshot lands
    /// (member mutations do not re-trigger `annotation.didSet`).
    func refresh() {
        guard let c = annotation as? MKClusterAnnotation else { return }
        let members = c.memberAnnotations.compactMap { $0 as? MeterAnnotation }
        let vacant = members.filter { $0.state == .vacant }.count
        label.text = vacant > 0 ? "\(vacant)" : "\(members.count)"
        backgroundColor = vacant > 0 ? UIColor(Brand.green) : UIColor(Brand.red)
    }
}
