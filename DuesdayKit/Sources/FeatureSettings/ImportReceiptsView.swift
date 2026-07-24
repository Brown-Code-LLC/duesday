import DesignSystem
import ReceiptImport
import SwiftUI
import UniformTypeIdentifiers

public struct ImportReceiptsView: View {
    @State private var isChoosingFile = false
    @State private var isProcessing = false
    @State private var resultMessage: String?
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text("Import receipts")
                .font(.dsTitle(30))
                .accessibilityAddTraits(.isHeader)
            Text("Choose a PDF, image, email file, HTML, or text receipt. Text extraction happens on this device; the source file is deleted immediately after processing, and anything found waits in Review.")
                .font(.dsBody(13.5))
                .foregroundStyle(Color.dsInkSecondary)
                .lineSpacing(4)
            Button {
                isChoosingFile = true
            } label: {
                if isProcessing { ProgressView() } else { Text("Choose a receipt") }
            }
            .buttonStyle(.dsPrimary)
            .disabled(isProcessing)
            if let resultMessage {
                Text(resultMessage)
                    .font(.dsBody(12.5))
                    .foregroundStyle(Color.dsInkSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.screenMargin)
        .padding(.top, DS.Spacing.md)
        .background(Color.dsPaper)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.pdf, .image, .plainText, .html, .emailMessage],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result { resultMessage = error.localizedDescription }
                return
            }
            process(url)
        }
    }

    private func process(_ url: URL) {
        isProcessing = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                isProcessing = false
            }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let store = try SecureImportStore()
                _ = try await ReceiptImportPipeline(context: modelContext, store: store)
                    .process(data: data, filename: url.lastPathComponent)
                resultMessage = "Processed. Any likely subscription is now waiting in Review."
                Haptics.success()
            } catch {
                resultMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}
