import CoreModels
import Foundation

/// The deterministic extraction pipeline (docs/05): normalize → detect
/// merchant/amount/frequency/dates/phrases → weight evidence → score.
/// Pure and synchronous; callers run it off the main actor.
public enum DetectionPipeline {
    // Evidence weights (candidate-level score, capped at 1).
    private enum Weight {
        static let trustedSenderDomain = 0.20
        static let recurringPhrase = 0.15
        static let labeledAmount = 0.20
        static let unlabeledAmount = 0.10
        static let explicitInterval = 0.20
        static let explicitRenewalDate = 0.15
        static let trialLanguage = 0.10
        static let headerBodyAgreement = 0.10
    }

    public static func analyze(_ input: EmailMessageInput) -> DetectionOutcome {
        // 1. Choose text: plain preferred, sanitized HTML fallback, and the
        //    subject always participates.
        let bodyText: String
        if let plain = input.plainText, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyText = TextNormalizer.normalize(plain)
        } else if let html = input.html {
            bodyText = HTMLTextExtractor.text(from: html)
        } else {
            bodyText = ""
        }
        let fullText = TextNormalizer.normalize(input.subject + "\n" + bodyText)

        // 2. Field extraction.
        let merchant = MerchantDetector.detect(from: input.from)
        let amount = AmountExtractor.detect(in: fullText)
        let frequency = FrequencyExtractor.detect(in: fullText)
        let renewalDate = DateExtractor.detect(in: fullText, context: DateExtractor.renewalContext)
        let trialDate = DateExtractor.detect(in: fullText, context: DateExtractor.trialContext)

        // 3. Phrase signals.
        let recurring = PhraseDetectors.recurringPhrase(in: fullText)
        let trial = PhraseDetectors.trialPhrase(in: fullText)
        let cancellation = PhraseDetectors.cancellationPhrase(in: fullText)
        let priceChange = PhraseDetectors.priceChangePhrase(in: fullText)
        let failed = PhraseDetectors.failedPaymentPhrase(in: fullText)
        let refund = PhraseDetectors.refundPhrase(in: fullText)
        let marketing = PhraseDetectors.marketingPhrase(in: fullText)

        // 4. Early exits for non-candidates.
        if let refund {
            return .notSubscription(reason: "Refund notice: \(refund)")
        }
        let hasBillingSignal = amount != nil || recurring != nil || trial != nil
            || cancellation != nil || priceChange != nil || failed != nil
        if !hasBillingSignal {
            return .notSubscription(reason: "No billing evidence found")
        }
        if marketing != nil && recurring == nil && frequency == nil && cancellation == nil && failed == nil {
            return .notSubscription(reason: "Marketing/shipping content without billing evidence")
        }

        // 5. Classification.
        let kind: MessageKind
        if failed != nil {
            kind = .paymentFailed
        } else if cancellation != nil {
            kind = .cancellation
        } else if priceChange != nil {
            kind = .priceChange
        } else if trial != nil || trialDate != nil {
            kind = .trialNotice
        } else if renewalDate != nil && amount == nil {
            kind = .renewalNotice
        } else {
            kind = .receipt
        }

        // 6. Evidence assembly + scoring.
        var evidence: [DetectionEvidence] = []
        var score = 0.0
        var fieldConfidence: [String: Double] = [:]

        if let merchant {
            evidence.append(DetectionEvidence(
                field: .merchant,
                reason: merchant.trusted ? .trustedSenderDomain : .merchantPattern,
                snippet: merchant.snippet,
                weight: merchant.trusted ? Weight.trustedSenderDomain : 0.05
            ))
            score += merchant.trusted ? Weight.trustedSenderDomain : 0.05
            fieldConfidence[DetectionEvidence.Field.merchant.rawValue] = merchant.confidence

            // Subject/sender agreement: merchant name echoed in the subject.
            if input.subject.range(of: merchant.name, options: .caseInsensitive) != nil {
                evidence.append(DetectionEvidence(
                    field: .merchant,
                    reason: .headerBodyAgreement,
                    snippet: String(input.subject.prefix(120)),
                    weight: Weight.headerBodyAgreement
                ))
                score += Weight.headerBodyAgreement
            }
        }

        if let amount {
            let weight = amount.labeled ? Weight.labeledAmount : Weight.unlabeledAmount
            evidence.append(DetectionEvidence(
                field: .amount,
                reason: .labeledAmount,
                snippet: amount.snippet,
                weight: weight
            ))
            score += weight
            fieldConfidence[DetectionEvidence.Field.amount.rawValue] = amount.labeled ? 0.9 : 0.6
            fieldConfidence[DetectionEvidence.Field.currency.rawValue] = 0.85
        }

        if let frequency {
            evidence.append(DetectionEvidence(
                field: .frequency,
                reason: .explicitInterval,
                snippet: frequency.snippet,
                weight: Weight.explicitInterval
            ))
            score += Weight.explicitInterval
            fieldConfidence[DetectionEvidence.Field.frequency.rawValue] = 0.9
        }

        if let recurring {
            evidence.append(DetectionEvidence(
                field: .frequency,
                reason: .recurringPhrase,
                snippet: recurring,
                weight: Weight.recurringPhrase
            ))
            score += Weight.recurringPhrase
        }

        if let renewalDate {
            evidence.append(DetectionEvidence(
                field: .nextBillingDate,
                reason: .explicitRenewalDate,
                snippet: renewalDate.snippet,
                weight: Weight.explicitRenewalDate
            ))
            score += Weight.explicitRenewalDate
            fieldConfidence[DetectionEvidence.Field.nextBillingDate.rawValue] = 0.85
        }

        if let trialDate {
            evidence.append(DetectionEvidence(
                field: .trialEnd,
                reason: .explicitRenewalDate,
                snippet: trialDate.snippet,
                weight: Weight.trialLanguage
            ))
            score += Weight.trialLanguage
            fieldConfidence[DetectionEvidence.Field.trialEnd.rawValue] = 0.85
        } else if let trial {
            evidence.append(DetectionEvidence(
                field: .trialEnd,
                reason: .recurringPhrase,
                snippet: trial,
                weight: Weight.trialLanguage
            ))
            score += Weight.trialLanguage
        }

        if let cancellation {
            evidence.append(DetectionEvidence(
                field: .cancellation,
                reason: .cancellationLanguage,
                snippet: cancellation,
                weight: 0.1
            ))
        }
        if let priceChange {
            evidence.append(DetectionEvidence(
                field: .priceChange,
                reason: .recurringPhrase,
                snippet: priceChange,
                weight: 0.1
            ))
        }

        let draft = CandidateDraft(
            sourceMessageID: input.messageID,
            kind: kind,
            merchantName: merchant?.name,
            amount: amount?.amount,
            currencyCode: amount?.currencyCode,
            frequency: frequency?.frequency,
            customInterval: frequency?.customInterval,
            nextBillingDate: renewalDate?.date,
            trialEndDate: trialDate?.date,
            messageDate: input.date,
            evidence: evidence,
            confidence: min(1, score),
            fieldConfidence: fieldConfidence
        )
        return .candidate(draft)
    }
}
