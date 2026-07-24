import CoreModels
import DesignSystem
import EmailProviders
import Persistence
import SwiftData
import SwiftUI

/// Connected accounts per the design spec (frame 1f): each account shows its
/// address, status, last sync, and first-class disconnect / delete-data
/// controls. Scope is restated at the moment of consent.
public struct ConnectedAccountsView: View {
    @Query(sort: [SortDescriptor(\UserAccount.createdAt)])
    private var accounts: [UserAccount]

    @State private var isConnecting = false
    @State private var isSyncing: UUID?
    @State private var disconnectTarget: UserAccount?
    @State private var actionError: String?
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Email accounts")
                    .font(.dsTitle(30))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, DS.Spacing.md)

                if accounts.isEmpty {
                    consentExplainer
                }
                ForEach(accounts) { account in
                    accountRow(account)
                }
                connectSection
                    .padding(.top, DS.Spacing.lg)
            }
            .padding(.horizontal, DS.screenMargin)
            .padding(.bottom, DS.Spacing.xl)
        }
        .background(Color.dsPaper)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Disconnect this account?",
            isPresented: disconnectBinding,
            titleVisibility: .visible
        ) {
            Button("Disconnect and delete found items", role: .destructive) {
                disconnect(purge: true)
            }
            Button("Disconnect, keep found items") {
                disconnect(purge: false)
            }
            Button("Cancel", role: .cancel) { disconnectTarget = nil }
        } message: {
            Text("Access is revoked either way. Deleting found items removes every detection imported from this account.")
        }
        .alert("Something went wrong", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Consent copy (scope restated at the moment of consent)

    private var consentExplainer: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Connecting Gmail gives Duesday read-only access, used for targeted searches of receipts, renewal notices, and trial confirmations — never your whole mailbox. Everything found waits in Review until you confirm it.")
                .font(.dsBody(13.5))
                .lineSpacing(4)
                .foregroundStyle(Color.dsInkSecondary)
            Text("Disconnect at any time; imported data can be deleted with it.")
                .font(.dsBody(12))
                .foregroundStyle(Color.dsInkTertiary)
        }
        .padding(.bottom, DS.Spacing.lg)
    }

    // MARK: - Account rows

    private func accountRow(_ account: UserAccount) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.dsRule).frame(height: 1)
            HStack(alignment: .top, spacing: 12) {
                DSGlyphBox(for: account.emailAddress.isEmpty ? "G" : account.emailAddress, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.emailAddress.isEmpty ? "Gmail account" : account.emailAddress)
                        .font(.dsBodyStrong(14.5))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        statusPill(account)
                        Text(lastSyncText(account))
                            .font(.dsBody(12))
                            .monospacedDigit()
                            .foregroundStyle(Color.dsInkTertiary)
                    }
                    Text("Read-only · receipts and renewals only")
                        .font(.dsBody(11.5))
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Spacer()
            }
            .padding(.vertical, DS.Spacing.md)

            HStack(spacing: 8) {
                Button {
                    sync(account)
                } label: {
                    if isSyncing == account.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(account.connectionStatus == .expired ? "Reconnect needed" : "Sync now")
                    }
                }
                .buttonStyle(DSCompactOutlineButtonStyle(tint: .dsAccentDeep))
                .disabled(isSyncing != nil || account.connectionStatus == .expired)

                Button("Disconnect…") { disconnectTarget = account }
                    .buttonStyle(DSCompactOutlineButtonStyle(tint: .dsDanger))
            }
            .padding(.bottom, DS.Spacing.md)
        }
    }

    @ViewBuilder
    private func statusPill(_ account: UserAccount) -> some View {
        switch account.connectionStatus {
        case .connected: DSTagPill("Connected", style: .accent)
        case .expired: DSTagPill("Sign in again", style: .neutral)
        case .revoked, .disconnected: DSTagPill("Disconnected", style: .neutral)
        case .error: DSTagPill("Error", style: .neutral)
        }
    }

    private func lastSyncText(_ account: UserAccount) -> String {
        guard let last = account.lastSyncDate else { return "never synced" }
        return "synced \(last.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Connect

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if service.isConfigured {
                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView().tint(Color.dsAccentDeep)
                    } else {
                        Text(accounts.isEmpty ? "Connect Gmail" : "Connect another account")
                    }
                }
                .buttonStyle(.dsPrimary)
                .disabled(isConnecting)
                Text("You'll sign in with Google. Duesday never sees your password, and requests read-only access.")
                    .font(.dsBody(11.5))
                    .foregroundStyle(Color.dsInkTertiary)
            } else {
                // Honest configuration-needed state: no dead primary button.
                Text("Gmail connection requires this build to be configured with a Google OAuth client ID (see docs/05-integration-strategy.md). Outlook support follows in a later update.")
                    .font(.dsBody(12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Color.dsInkSecondary)
            }
        }
    }

    // MARK: - Actions

    private var service: GmailAccountService {
        GmailAccountService(context: modelContext)
    }

    private func connect() {
        isConnecting = true
        Task {
            do {
                _ = try await service.connect()
                Haptics.success()
            } catch {
                actionError = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func sync(_ account: UserAccount) {
        isSyncing = account.id
        Task {
            do {
                _ = try await service.sync(account: account)
                Haptics.success()
            } catch {
                actionError = error.localizedDescription
            }
            isSyncing = nil
        }
    }

    private func disconnect(purge: Bool) {
        guard let account = disconnectTarget else { return }
        disconnectTarget = nil
        Task {
            do {
                try await service.disconnect(account: account, purgeImportedData: purge)
                Haptics.success()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private var disconnectBinding: Binding<Bool> {
        Binding(
            get: { disconnectTarget != nil },
            set: { if !$0 { disconnectTarget = nil } }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )
    }
}
