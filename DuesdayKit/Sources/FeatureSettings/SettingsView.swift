import AppSecurity
import CoreModels
import DesignSystem
import Notifications
import Persistence
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings per the design spec: caption-and-rule sections of hairline rows —
/// accounts & detection, preferences (reminders, Face ID), first-class data
/// controls (export, deletion), and a colophon footer.
public struct SettingsView: View {
    /// Non-nil when the persistent store failed and the app is running on a
    /// temporary in-memory store (PersistenceController.bootstrap).
    private let storageWarning: String?
    private let appLock: AppLockModel
    private let onPreferencesChanged: () -> Void

    @State private var exportDocument: ExportDocument?
    @State private var isExporting = false
    @State private var isConfirmingErase = false
    @State private var actionError: String?
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [UserAccount]

    private var accountCountText: String? {
        accounts.isEmpty ? nil : "\(accounts.count)"
    }

    public init(
        storageWarning: String? = nil,
        appLock: AppLockModel = AppLockModel(),
        onPreferencesChanged: @escaping () -> Void = {}
    ) {
        self.storageWarning = storageWarning
        self.appLock = appLock
        self.onPreferencesChanged = onPreferencesChanged
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.dsTitle(30))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.md)

                    if let storageWarning {
                        Text(storageWarning)
                            .font(.dsBody(12.5))
                            .foregroundStyle(Color.dsDanger)
                            .padding(.bottom, DS.Spacing.md)
                    }

                    DSSectionHeader("Accounts & detection")
                    NavigationLink {
                        ConnectedAccountsView()
                    } label: {
                        chevronRow("Connected email accounts", detail: accountCountText)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        ImportReceiptsView()
                    } label: {
                        chevronRow("Import receipt or email")
                    }
                    .buttonStyle(.plain)

                    DSSectionHeader("Preferences")
                        .padding(.top, DS.Spacing.lg)
                    NavigationLink {
                        NotificationSettingsView(onPreferencesChanged: onPreferencesChanged)
                    } label: {
                        chevronRow("Notifications")
                    }
                    .buttonStyle(.plain)
                    faceIDRow

                    DSSectionHeader("Your data")
                        .padding(.top, DS.Spacing.lg)
                    actionRow("Export ledger (CSV)") { export(as: .commaSeparatedText) }
                    actionRow("Export ledger (JSON)") { export(as: .json) }
                    actionRow("Delete everything", tint: .dsDanger) { isConfirmingErase = true }

                    NavigationLink {
                        PrivacyExplanationView()
                    } label: {
                        HStack(spacing: DS.Spacing.lg) {
                            Text("Privacy")
                            Text("Permissions")
                            Spacer()
                        }
                        .font(.dsBody(13))
                        .foregroundStyle(Color.dsInkSecondary)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Privacy and permissions")

                    colophon
                        .padding(.top, DS.Spacing.xxl)
                }
                .padding(.horizontal, DS.screenMargin)
                .padding(.bottom, DS.Spacing.xl)
            }
            .background(Color.dsPaper)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportDocument?.contentType ?? .json,
                defaultFilename: exportDocument?.filename ?? "duesday-export"
            ) { result in
                if case .failure(let error) = result {
                    actionError = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Delete all data?",
                isPresented: $isConfirmingErase,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { eraseAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every entry, reminder, and detection from this device. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: alertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    // MARK: - Rows

    private func chevronRow(_ title: String, detail: String? = nil) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.dsBody(14.5))
                    .foregroundStyle(Color.dsInk)
                Spacer()
                Text("\(detail.map { "\($0) " } ?? "")›")
                    .font(.dsBody(14))
                    .foregroundStyle(Color.dsInkSecondary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    private func infoRow(title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dsBody(14.5))
                Text(subtitle)
                    .font(.dsBody(12))
                    .foregroundStyle(Color.dsInkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ title: String, tint: Color = .dsInk, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chevronRow("")
                .overlay(alignment: .leading) {
                    Text(title)
                        .font(.dsBody(14.5))
                        .foregroundStyle(tint)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var faceIDRow: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock with \(appLock.biometryDescription)")
                        .font(.dsBody(14.5))
                    Text("Required to open Duesday")
                        .font(.dsBody(12))
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Spacer()
                Toggle("", isOn: appLockBinding)
                    .labelsHidden()
                    .tint(.dsAccent)
                    .disabled(!appLock.isAvailable)
                    .accessibilityLabel("Lock with \(appLock.biometryDescription)")
            }
            .padding(.vertical, 12)
            if let lockError = appLock.lastError {
                Text(lockError)
                    .font(.dsBody(12))
                    .foregroundStyle(Color.dsDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Spacing.xs)
            }
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
    }

    private var colophon: some View {
        VStack(spacing: 3) {
            Text("Duesday")
                .font(.dsSerif(14))
                .foregroundStyle(Color.dsInkSecondary)
            Text("\(appVersion) · Your ledger stays yours.")
                .font(.dsBody(11))
                .monospacedDigit()
                .foregroundStyle(Color.dsInkTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func export(as type: UTType) {
        let exporter = DataExporter(context: modelContext)
        do {
            if type == .json {
                exportDocument = ExportDocument(
                    data: try exporter.jsonData(appVersion: appVersion),
                    contentType: .json,
                    filename: "duesday-export.json"
                )
            } else {
                exportDocument = ExportDocument(
                    data: try exporter.csvData(),
                    contentType: .commaSeparatedText,
                    filename: "duesday-export.csv"
                )
            }
            isExporting = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func eraseAll() {
        do {
            try DataEraser(context: modelContext).eraseAll()
            Task { await ReminderScheduler().removeAllReminders() }
            Haptics.success()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLock.isEnabled },
            set: { newValue in
                Task { await appLock.setEnabled(newValue) }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "—"
        }
    }
}

/// Wraps export bytes for the system file exporter.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let data: Data
    let contentType: UTType
    let filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = .json
        filename = "duesday-export.json"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
