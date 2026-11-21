//
//  LCHomeView.swift
//  Deck — iPhone-style home screen for LiveContainer
//
//  Paged icon grid, glass dock, wallpapers, page dots.
//  Tapping an icon runs the guest app through the same
//  LCAppModel.runApp path the Apps list uses.
//

import SwiftUI
import UIKit

// MARK: - Home

struct LCHomeView: View, LCAppModelDelegate {
    @EnvironmentObject var sharedModel: SharedModel
    @ObservedObject private var sortManager = LCAppSortManager.shared

    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false
    @AppStorage("DeckWallpaper", store: LCUtils.appGroupUserDefault) private var wallpaperIndex = 0

    // launch errors
    @State private var launchError = ""
    @State private var launchErrorShow = false

    // delegate-driven alerts (same helpers the Apps list uses)
    @StateObject private var runWhenMultitaskAlert = YesNoHelper()
    @StateObject private var jitAlert = YesNoHelper()
    @State private var jitLog = ""

    // per-app settings sheet
    @State private var settingsModel: LCAppModel? = nil
    @State private var settingsPresented = false

    // paging
    @State private var selectedPage = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var apps: [LCAppModel] { sortManager.sortedApps }

    var body: some View {
        GeometryReader { geo in
            let pageSize = pageSize(for: geo.size.height)
            let pages = chunk(apps, pageSize)

            ZStack {
                wallpaper
                    .contextMenu {
                        Button {
                            wallpaperIndex = 0
                        } label: {
                            Label("Midnight", systemImage: wallpaperIndex == 0 ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            wallpaperIndex = 1
                        } label: {
                            Label("Sunset", systemImage: wallpaperIndex == 1 ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            wallpaperIndex = 2
                        } label: {
                            Label("Emerald", systemImage: wallpaperIndex == 2 ? "checkmark.circle.fill" : "circle")
                        }
                        Divider()
                        Button {
                            sharedModel.selectedTab = .apps
                        } label: {
                            Label("App Library", systemImage: "square.grid.2x2")
                        }
                    }

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, 6)

                    Spacer(minLength: 12)

                    if apps.isEmpty {
                        emptyState
                        Spacer(minLength: 12)
                    } else {
                        pager(pages: pages, pageSize: pageSize)
                            .frame(height: CGFloat(pageSize / 4) * 92 + 8)

                        pageDots(count: pages.count)
                            .padding(.bottom, 16)
                    }

                    dock
                        .padding(.bottom, 14)

                    homeIndicator
                }
                .padding(.horizontal, 12)
            }
        }
        .onAppear(perform: claimDelegates)
        .onChange(of: apps.count) { _ in
            let count = chunk(apps, pageSizeSafe).count
            if selectedPage >= count {
                selectedPage = max(0, count - 1)
            }
        }
        .alert("lc.common.error".loc, isPresented: $launchErrorShow) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text(launchError)
        }
        .alert("lc.appList.runApp".loc, isPresented: $runWhenMultitaskAlert.show) {
            Button(role: .destructive) {
                runWhenMultitaskAlert.close(result: true)
            } label: {
                Text("lc.common.continue".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                runWhenMultitaskAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmRunWhenMultitasking".loc)
        }
        .sheet(isPresented: $jitAlert.show, onDismiss: {
            jitAlert.close(result: false)
        }) {
            jitModal
        }
        .sheet(isPresented: $settingsPresented, onDismiss: {
            settingsModel = nil
        }) {
            if let settingsModel {
                LCAppSettingsView(model: settingsModel)
            }
        }
        .modifier(HideTabBarModifier())
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                sharedModel.selectedTab = .apps
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Search")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            glassCircleButton(systemImage: "square.grid.2x2.fill") {
                sharedModel.selectedTab = .apps
            }
            glassCircleButton(systemImage: "gearshape.fill") {
                sharedModel.selectedTab = .settings
            }
        }
    }

    private func glassCircleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pager

    private func pager(pages: [[LCAppModel]], pageSize: Int) -> some View {
        TabView(selection: Binding(
            get: { min(selectedPage, max(pages.count - 1, 0)) },
            set: { selectedPage = $0 }
        )) {
            ForEach(0..<max(pages.count, 1), id: \.self) { index in
                if index < pages.count {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(pages[index], id: \.self) { app in
                            HomeIconCell(
                                app: app,
                                darkModeIcon: darkModeIcon,
                                showLabel: true,
                                onTap: { launch(app) },
                                onSettings: { openSettings(app) }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .tag(index)
                } else {
                    Color.clear.tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == selectedPage ? 0.95 : 0.35))
                    .frame(width: 6.5, height: 6.5)
            }
        }
    }

    // MARK: - Dock

    private var dock: some View {
        let dockApps = Array(apps.prefix(4))
        return HStack(spacing: 26) {
            ForEach(0..<4, id: \.self) { index in
                if index < dockApps.count {
                    HomeIconCell(
                        app: dockApps[index],
                        darkModeIcon: darkModeIcon,
                        showLabel: false,
                        onTap: { launch(dockApps[index]) },
                        onSettings: { openSettings(dockApps[index]) }
                    )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                        .opacity(0.55)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(.white.opacity(0.9))
            .frame(width: 134, height: 5)
            .padding(.bottom, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("No Apps Yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Open the App Library to install\nIPA files or add a repository.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                sharedModel.selectedTab = .apps
            } label: {
                Text("Open App Library")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.92), in: Capsule())
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(.horizontal, 36)
    }

    // MARK: - Wallpapers

    private var wallpaper: some View {
        Group {
            switch wallpaperIndex {
            case 1:
                sunsetWallpaper
            case 2:
                emeraldWallpaper
            default:
                midnightWallpaper
            }
        }
        .animation(.easeInOut(duration: 0.35), value: wallpaperIndex)
    }

    private var midnightWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.20),
                    Color(red: 0.13, green: 0.09, blue: 0.30),
                    Color(red: 0.04, green: 0.04, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.36, green: 0.24, blue: 0.96).opacity(0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -110, y: -300)
            Circle()
                .fill(Color(red: 0.10, green: 0.55, blue: 0.98).opacity(0.45))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 150, y: 260)
            Circle()
                .fill(Color(red: 0.88, green: 0.32, blue: 0.78).opacity(0.30))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: 70, y: -40)
        }
    }

    private var sunsetWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.10, blue: 0.24),
                    Color(red: 0.55, green: 0.18, blue: 0.24),
                    Color(red: 0.12, green: 0.06, blue: 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.55))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: 120, y: -240)
            Circle()
                .fill(Color(red: 0.95, green: 0.25, blue: 0.45).opacity(0.45))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: -140, y: 220)
            Circle()
                .fill(Color(red: 0.55, green: 0.20, blue: 0.85).opacity(0.40))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: -40, y: -60)
        }
    }

    private var emeraldWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.16, blue: 0.14),
                    Color(red: 0.05, green: 0.24, blue: 0.20),
                    Color(red: 0.02, green: 0.08, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.10, green: 0.85, blue: 0.60).opacity(0.45))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -120, y: -280)
            Circle()
                .fill(Color(red: 0.15, green: 0.55, blue: 0.95).opacity(0.40))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 140, y: 250)
            Circle()
                .fill(Color(red: 0.65, green: 0.95, blue: 0.35).opacity(0.25))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .offset(x: 40, y: -30)
        }
    }

    // MARK: - Layout math

    /// How many app pages fit vertically at the given screen height.
    private func pageSize(for height: CGFloat) -> Int {
        let topChrome: CGFloat = 58          // search + glass buttons
        let bottomChrome: CGFloat = 16 + 26 + 96 + 28  // dots + dock + indicator + padding
        let usable = height - topChrome - bottomChrome
        let rows = max(3, min(6, Int(usable / 92)))
        return rows * 4
    }

    /// Fallback for onChange before GeometryReader reports.
    private var pageSizeSafe: Int { 24 }

    private func chunk(_ array: [LCAppModel], _ size: Int) -> [[LCAppModel]] {
        guard size > 0, !array.isEmpty else { return array.isEmpty ? [] : [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }

    // MARK: - Actions

    private func claimDelegates() {
        // LCAppListView stamps itself as delegate when it appears;
        // claim any app that has no delegate yet so taps from Home work.
        for app in DataManager.shared.model.apps where app.delegate == nil {
            app.delegate = self
        }
        for app in DataManager.shared.model.hiddenApps where app.delegate == nil {
            app.delegate = self
        }
    }

    private func launch(_ app: LCAppModel) {
        if app.delegate == nil {
            app.delegate = self
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                try await app.runApp(multitask: nil, containerFolderName: nil)
            } catch {
                await MainActor.run {
                    launchError = error.localizedDescription
                    launchErrorShow = true
                }
            }
        }
    }

    private func openSettings(_ app: LCAppModel) {
        settingsModel = app
        settingsPresented = true
    }

    // MARK: - LCAppModelDelegate (JIT / multitask plumbing)

    func closeNavigationView() {}

    func changeAppVisibility(app: LCAppModel) {}

    func jitLaunch(appName: String, classicMode: UInt) async {
        await jitLaunch(withScript: "", appName: appName, classicMode: classicMode)
    }

    func jitLaunch(withScript script: String, appName: String, classicMode: UInt) async {
        await MainActor.run {
            jitLog = ""
        }
        let enableJITTask = Task {
            let _ = await LCUtils.askForJIT(withScript: script, appName: appName, classicMode: classicMode) { newMsg in
                Task { await MainActor.run {
                    self.jitLog += "\(newMsg)\n"
                }}
            }
        }
        guard let result = await jitAlert.open(), result else {
            UserDefaults.standard.removeObject(forKey: "selected")
            enableJITTask.cancel()
            return
        }
        LCSharedUtils.launchToGuestApp(withClassicMode: classicMode)
    }

    func jitLaunch(withPID pid: Int, withScript script: String? = nil, appName: String) async {
        await MainActor.run {
            guard let jitEnabler = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")) else {
                return
            }
            let encodedData = script?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)

            switch jitEnabler {
            case .StosDebug, .StikJIT:
                let query = jitEnabler == .StosDebug
                    ? "stosdebug://enableJIT?bundleId=\(Bundle.main.bundleIdentifier!)&appName=\(appName)&pid=\(pid)&relaunchApp=false& forcePID=true"
                    : "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)&pid=\(pid)"
                let scriptPart = encodedData.map { jitEnabler == .StosDebug ? "&script=\($0)" : "&script-data=\($0)" } ?? ""
                if let url = URL(string: query + scriptPart) {
                    UIApplication.shared.open(url)
                }
            default:
                // StosDebugLC / StikJITLC variants need the in-app web view,
                // which lives in the Apps tab.
                launchError = "This JIT enabler needs the Apps tab. Launch the app from the Apps list instead."
                launchErrorShow = true
            }
        }
    }

    func showRunWhenMultitaskAlert() async -> Bool? {
        return await runWhenMultitaskAlert.open()
    }

    // MARK: - JIT modal (mirrors the Apps list one)

    private var jitModal: some View {
        NavigationView {
            ScrollView {
                Text("lc.appBanner.waitForJitMsg".loc)
                    .padding(.vertical)
                HStack {
                    Text(jitLog)
                        .font(.system(size: 12).monospaced())
                        .fixedSize(horizontal: false, vertical: false)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .navigationTitle("lc.appBanner.waitForJitTitle".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("lc.common.cancel".loc, role: .cancel) {
                        jitAlert.close(result: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        jitAlert.close(result: true)
                    } label: {
                        Text("lc.appBanner.jitLaunchNow".loc)
                    }
                }
            }
        }
    }
}

// MARK: - Icon cell

struct HomeIconCell: View {
    @ObservedObject var app: LCAppModel
    let darkModeIcon: Bool
    let showLabel: Bool
    let onTap: () -> Void
    let onSettings: () -> Void

    @State private var icon: UIImage? = nil
    @State private var pressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let icon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Image(systemName: "app.dashed")
                                        .font(.system(size: 22, weight: .light))
                                        .foregroundStyle(.white.opacity(0.7))
                                )
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)

                    if app.isAppRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }

                if showLabel {
                    Text(app.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .frame(maxWidth: 74)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.90 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                    }
                }
                .onEnded { _ in
                    pressed = false
                }
        )
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Open", systemImage: "play.fill")
            }
            Button {
                onSettings()
            } label: {
                Label("App Settings", systemImage: "gearshape")
            }
        }
        .task(id: darkModeIcon) {
            if let cached = IconCacheManager.shared.getIcon(for: app.appInfo.relativeBundlePath ?? app.displayName) {
                icon = cached
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) {
                app.appInfo.iconIsDarkIcon(darkModeIcon)
            }.value
            if let loaded {
                icon = loaded
                IconCacheManager.shared.setIcon(loaded, for: app.appInfo.relativeBundlePath ?? app.displayName)
            }
        }
    }
}

// MARK: - Hide tab bar while Home is visible (iOS 16+)

private struct HideTabBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}
