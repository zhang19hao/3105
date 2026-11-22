import SwiftUI
import UIKit

struct AppDataBrowserView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var isResolving = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var workspaceURL: URL?
    @State private var isShowingPathJump = false
    @State private var pathJumpInput = ""
    @State private var pathJumpError: String?
    @State private var isResolvingPath = false
    @State private var recentPaths: [String] = PathJumpRecents.load()
    @Binding private var tabSession: FilesTabSession
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    init(
        tabSession: Binding<FilesTabSession>,
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        _tabSession = tabSession
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
    }

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        let q = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    private var overlayState: AppBrowserOverlayState {
        if (isLoading || isResolving) && apps.isEmpty { return .loading }
        if apps.isEmpty { return .empty }
        if filteredApps.isEmpty { return .noResults }
        return .none
    }

    private var interfaceAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.20)
    }

    var body: some View {
        navigationContent(tabID: tabSession.selectedTabID)
            .id(tabSession.selectedTabID)
    }

    private func navigationContent(tabID: UUID) -> some View {
        NavigationStack(path: navigationPath(for: tabID)) {
            appList
            .navigationTitle(language.text("browser.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    FilesTabToolbarButton(session: $tabSession)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reload() } label: {
                        if isResolving {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isResolving)
                    .accessibilityLabel(language.text("browser.retry"))
                }
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .onAppear {
                if workspaceURL == nil {
                    workspaceURL = try? PatchWorkspaceService.documentsRootURL()
                    _ = try? PatchWorkspaceService.patchesRootURL()
                }
                if !hasLoaded {
                    hasLoaded = true
                    reload()
                }
            }
            .navigationDestination(for: FileBrowserDestination.self) { destination in
                if destination.startPath == destination.containerPath {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        filesTabSession: $tabSession
                    )
                } else {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        startPath: destination.startPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        filesTabSession: $tabSession
                    )
                }
            }
            .sheet(isPresented: $isShowingPathJump) {
                pathJumpSheet
            }
        }
    }

    private func navigationPath(for tabID: UUID) -> Binding<[FileBrowserDestination]> {
        Binding(
            get: { tabSession.navigationPath(for: tabID) },
            set: { tabSession.setNavigationPath($0, for: tabID) }
        )
    }

    private var appList: some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                FilesTabStrip(session: $tabSession)
            }
            AppSearchField(
                text: $searchText,
                prompt: language.text("browser.search"),
                clearLabel: language.text("common.clear")
            )
            Divider()
            appRows
        }
    }

    private var appRows: some View {
        List {
            Section {
                Button {
                    pathJumpInput = ""
                    pathJumpError = nil
                    recentPaths = PathJumpRecents.load()
                    isShowingPathJump = true
                } label: {
                    HStack(spacing: 10) {
                        AppRowIcon(systemName: "arrow.turn.down.right")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pathJumpStrings.rowTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(pathJumpStrings.rowSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let workspaceURL {
                Section(language.text("browser.workspace")) {
                    let workspaceDestination = FileBrowserDestination(
                        containerPath: workspaceURL.path,
                        startPath: workspaceURL.path,
                        title: "3105",
                        bundleID: nil
                    )
                    NavigationLink(value: workspaceDestination) {
                        HStack(spacing: 10) {
                            AppRowIcon(systemName: "folder.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("3105")
                                    .font(.subheadline.weight(.semibold))
                                Text(language.text("browser.workspace_subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        openInNewTabButton(workspaceDestination)
                    }
                }
            }
            Section {
                ForEach(filteredApps) { app in
                    if app.containerPath.isEmpty {
                        appRow(app)
                    } else {
                        let appDestination = FileBrowserDestination(
                            containerPath: app.containerPath,
                            startPath: app.containerPath,
                            title: app.displayName,
                            bundleID: app.bundleID
                        )
                        NavigationLink(value: appDestination) {
                            appRow(app)
                        }
                        .contextMenu {
                            openInNewTabButton(appDestination)
                        }
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(language.text("browser.apps_count", Int64(filteredApps.count)))
                    Spacer()
                    if isResolving {
                        ProgressView()
                            .controlSize(.mini)
                        Text(language.text("browser.mha_scanning"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 48)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            Group {
                switch overlayState {
                case .loading:
                    ProgressView(language.text("browser.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    emptyView
                case .noResults:
                    searchEmptyView
                case .none:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .animation(interfaceAnimation, value: overlayState)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            BrowserAppIcon(app: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(app.bundleID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !app.version.isEmpty {
                Text(app.version)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
    }

    private func openInNewTabButton(_ destination: FileBrowserDestination) -> some View {
        Button {
            tabSession.openTab(navigationPath: [destination])
        } label: {
            Label(language.text("browser.open_new_tab"), systemImage: "square.on.square")
        }
    }

    // MARK: - Open specified path

    private var pathJumpStrings: PathJumpStrings {
        PathJumpStrings(language: language)
    }

    private var pathJumpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(pathJumpStrings.placeholder, text: $pathJumpInput)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { openSpecifiedPath() }
                } footer: {
                    Text(pathJumpStrings.footer)
                }

                if let pathJumpError {
                    Section {
                        Label(pathJumpError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !recentPaths.isEmpty {
                    Section {
                        ForEach(recentPaths, id: \.self) { recentPath in
                            Button {
                                pathJumpInput = recentPath
                            } label: {
                                Text(recentPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    } header: {
                        Text(pathJumpStrings.recentTitle)
                    }
                }

                Section {
                    Button {
                        openSpecifiedPath()
                    } label: {
                        HStack {
                            Spacer()
                            if isResolvingPath {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(pathJumpStrings.openTitle)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        isResolvingPath
                            || pathJumpInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                    )
                }
            }
            .navigationTitle(pathJumpStrings.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(pathJumpStrings.cancelTitle) {
                        isShowingPathJump = false
                    }
                    .disabled(isResolvingPath)
                }
            }
            .interactiveDismissDisabled(isResolvingPath)
        }
    }

    private func openSpecifiedPath() {
        let raw = pathJumpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard raw.hasPrefix("/") else {
            pathJumpError = pathJumpStrings.invalidPath
            return
        }
        let path = (raw as NSString).standardizingPath
        pathJumpError = nil
        isResolvingPath = true
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = ContainerStore.grantContainerAccess(path)
            log("pathjump: traversal grant " + path + " -> " + String(handle))
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: path,
                isDirectory: &isDirectory
            )
            let listing: [FileEntry] = exists ? [] : ContainerStore.listFiles(at: path)
            DispatchQueue.main.async {
                isResolvingPath = false
                if exists && isDirectory.boolValue {
                    presentPathJump(path)
                } else if exists {
                    pathJumpError = pathJumpStrings.notDirectory
                } else if listing.isEmpty {
                    pathJumpError = pathJumpStrings.notFound
                } else {
                    presentPathJump(path)
                }
            }
        }
    }

    private func presentPathJump(_ path: String) {
        let displayName = (path as NSString).lastPathComponent
        let destination = FileBrowserDestination(
            containerPath: path,
            startPath: path,
            title: displayName.isEmpty ? "/" : displayName,
            bundleID: nil
        )
        let tabID = tabSession.selectedTabID
        var navigationPath = tabSession.navigationPath(for: tabID)
        navigationPath.append(destination)
        tabSession.setNavigationPath(navigationPath, for: tabID)
        PathJumpRecents.store(path)
        recentPaths = PathJumpRecents.load()
        isShowingPathJump = false
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(errorMessage ?? language.text("browser.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button(language.text("browser.retry")) { reload() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var searchEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("browser.search_empty"))
                .font(.subheadline.weight(.medium))
            Text(language.text("browser.search_apps_empty_message"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func reload() {
        isLoading = true
        isResolving = true
        errorMessage = nil
        let emptyMessage = language.text("browser.empty")
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleMetadata = ContainerStore.applicationBundleMetadataCatalog()
            let apiApps = ContainerStore.applyingBundleMetadata(
                to: ContainerStore.installedAppsFromAPI(),
                catalog: bundleMetadata
            )
            if apiApps.isEmpty {
                log("browser: installed-app API unavailable; trying MCM class-2 enumeration...")
            }
            let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
            let mcmApps = ContainerStore.installedAppsFromMCM(
                identifiers: dynamicIdentifiers,
                bundleMetadata: bundleMetadata
            )
            let filesystemApps = ContainerStore.containersFromFilesystem()
            let baseIdentifiedApps = mcmApps + apiApps
            var result = ContainerDiscoveryMerger.merge(
                enumerated: filesystemApps,
                identified: baseIdentifiedApps,
                path: { $0.containerPath }
            )
            log("browser: merged api=\(apiApps.count), MCM=\(mcmApps.count), filesystem=\(filesystemApps.count) -> \(result.count)")
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let preliminary = result.filter {
                ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
            }
            DispatchQueue.main.async {
                apps = preliminary
                isLoading = false
            }

            let launchServicesIdentifiers = ContainerStore.launchServicesStoreIdentifiers()
            let mhaIdentifiers = MHAIdentifierCatalog.identifiers(
                dynamic: dynamicIdentifiers,
                installed: apiApps.map(\.bundleID),
                research: ContainerStore.researchAppIdentifiers,
                custom: bundleMetadata.keys.sorted(),
                launchServices: launchServicesIdentifiers
            )
            log(
                "browser: MHA catalog dynamic=\(dynamicIdentifiers.count), " +
                "installed=\(apiApps.count), research=\(ContainerStore.researchAppIdentifiers.count), " +
                "LaunchServices=\(launchServicesIdentifiers.count) -> \(mhaIdentifiers.count) candidates"
            )
            let mhaApps = ContainerStore.installedAppsFromMHACandidates(
                identifiers: mhaIdentifiers,
                bundleMetadata: bundleMetadata
            ) { discoveredApps in
                var progressiveResult = AppDataCatalogMerger.merge(
                    identified: discoveredApps + baseIdentifiedApps,
                    fallback: [],
                    identifier: { $0.bundleID },
                    path: { $0.containerPath }
                )
                progressiveResult = progressiveResult.filter {
                    ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
                }
                progressiveResult.sort {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                DispatchQueue.main.async {
                    apps = progressiveResult
                }
            }

            let allKnownApps = mhaApps + baseIdentifiedApps
            let identifiedPaths = Set(allKnownApps.map {
                ContainerDiscoveryMerger.canonicalPath($0.containerPath)
            })
            let unmatchedFilesystemApps = filesystemApps.filter {
                !identifiedPaths.contains(
                    ContainerDiscoveryMerger.canonicalPath($0.containerPath)
                )
            }
            let inferredFilesystemApps = ContainerStore.inferUnidentifiedApps(
                in: unmatchedFilesystemApps,
                knownApps: allKnownApps,
                launchServicesIdentifiers: Set(launchServicesIdentifiers)
            ).filter {
                ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
            }
            result = AppDataCatalogMerger.merge(
                identified: allKnownApps,
                fallback: inferredFilesystemApps,
                identifier: { $0.bundleID },
                path: { $0.containerPath }
            )
            result = result.filter {
                ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
            }
            result.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            DispatchQueue.main.async {
                apps = result
                isLoading = false
                isResolving = false
                if result.isEmpty {
                    errorMessage = emptyMessage
                }
            }
        }
    }
}

private enum AppBrowserOverlayState: Equatable {
    case loading
    case empty
    case noResults
    case none
}

struct BrowserAppIcon: View {
    let app: InstalledApp
    @State private var resolvedIcon: UIImage?
    @State private var didRequestIcon = false

    init(app: InstalledApp) {
        self.app = app
        _resolvedIcon = State(initialValue: app.icon)
    }

    var body: some View {
        Group {
            if let resolvedIcon {
                Image(uiImage: resolvedIcon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app")
                    .font(.system(size: AppTheme.rowIconSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: AppTheme.appIconSize, height: AppTheme.appIconSize)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard resolvedIcon == nil, !didRequestIcon else { return }
            didRequestIcon = true
            let bundleID = app.bundleID
            DispatchQueue.global(qos: .utility).async {
                let icon = iconForBundleID(bundleID)
                DispatchQueue.main.async {
                    resolvedIcon = icon
                }
            }
        }
    }
}

private enum PathJumpRecents {
    private static let storageKey = "pathJumpRecents"
    private static let limit = 6

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    static func store(_ path: String) {
        var list = load().filter { $0 != path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: storageKey)
    }
}

private struct PathJumpStrings {
    let navTitle: String
    let rowTitle: String
    let rowSubtitle: String
    let placeholder: String
    let footer: String
    let openTitle: String
    let cancelTitle: String
    let invalidPath: String
    let notDirectory: String
    let notFound: String
    let recentTitle: String

    init(language: AppLanguage) {
        switch language {
        case .simplifiedChinese:
            navTitle = "打开指定路径"
            rowTitle = "打开指定路径"
            rowSubtitle = "输入绝对路径直接浏览"
            placeholder = "/var/mobile/Containers/..."
            footer = "路径需要是绝对路径，以 / 开头。"
            openTitle = "打开"
            cancelTitle = "取消"
            invalidPath = "路径需以 / 开头。"
            notDirectory = "该路径是文件，不是文件夹。"
            notFound = "路径不存在或没有访问权限。"
            recentTitle = "最近路径"
        case .vietnamese:
            navTitle = "Mở đường dẫn"
            rowTitle = "Mở đường dẫn chỉ định"
            rowSubtitle = "Nhập đường dẫn tuyệt đối để duyệt"
            placeholder = "/var/mobile/Containers/..."
            footer = "Đường dẫn phải là tuyệt đối và bắt đầu bằng /."
            openTitle = "Mở"
            cancelTitle = "Hủy"
            invalidPath = "Đường dẫn phải bắt đầu bằng /."
            notDirectory = "Đường dẫn này là tệp, không phải thư mục."
            notFound = "Không tìm thấy đường dẫn hoặc không có quyền truy cập."
            recentTitle = "Đường dẫn gần đây"
        case .english:
            navTitle = "Go to Path"
            rowTitle = "Open specified path"
            rowSubtitle = "Enter an absolute path to browse"
            placeholder = "/var/mobile/Containers/..."
            footer = "The path must be absolute and start with /."
            openTitle = "Open"
            cancelTitle = "Cancel"
            invalidPath = "The path must start with /."
            notDirectory = "That path is a file, not a folder."
            notFound = "Path not found or access denied."
            recentTitle = "Recent paths"
        }
    }
}
