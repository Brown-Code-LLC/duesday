import CoreModels
import Foundation

/// Normalized input to the pipeline — provider-agnostic, so Gmail, Microsoft,
/// and document imports all funnel through the same stages.
public struct EmailMessageInput: Sendable {
    public let messageID: String
    /// Raw From header, e.g. `Netflix <info@account.netflix.com>`.
    public let from: String
    public let subject: String
    public let date: Date?
    public let plainText: String?
    public let html: String?

    public init(
        messageID: String,
        from: String,
        subject: String,
        date: Date?,
        plainText: String?,
        html: String?
    ) {
        self.messageID = messageID
        self.from = from
        self.subject = subject
        self.date = date
        self.plainText = plainText
        self.html = html
    }
}

/// What kind of subscription-related message this is.
public enum MessageKind: String, Sendable {
    case receipt
    case renewalNotice
    case trialNotice
    case cancellation
    case priceChange
    case paymentFailed
    case refund
}

/// Extraction result before persistence. Missing fields stay nil — the
/// pipeline never invents values (spec: detection pipeline).
public struct CandidateDraft: Sendable {
    public var sourceMessageID: String
    public var kind: MessageKind
    public var merchantName: String?
    public var amount: Decimal?
    public var currencyCode: String?
    public var frequency: BillingFrequency?
    public var customInterval: CustomInterval?
    public var nextBillingDate: Date?
    public var trialEndDate: Date?
    public var messageDate: Date?
    public var evidence: [DetectionEvidence]
    public var confidence: Double
    public var fieldConfidence: [String: Double]

    public init(
        sourceMessageID: String,
        kind: MessageKind,
        merchantName: String?,
        amount: Decimal?,
        currencyCode: String?,
        frequency: BillingFrequency?,
        customInterval: CustomInterval?,
        nextBillingDate: Date?,
        trialEndDate: Date?,
        messageDate: Date?,
        evidence: [DetectionEvidence],
        confidence: Double,
        fieldConfidence: [String: Double]
    ) {
        self.sourceMessageID = sourceMessageID
        self.kind = kind
        self.merchantName = merchantName
        self.amount = amount
        self.currencyCode = currencyCode
        self.frequency = frequency
        self.customInterval = customInterval
        self.nextBillingDate = nextBillingDate
        self.trialEndDate = trialEndDate
        self.messageDate = messageDate
        self.evidence = evidence
        self.confidence = confidence
        self.fieldConfidence = fieldConfidence
    }
}

public enum DetectionOutcome: Sendable {
    case candidate(CandidateDraft)
    /// Recognized but not something to add (refunds, shipping, marketing).
    case notSubscription(reason: String)
}
