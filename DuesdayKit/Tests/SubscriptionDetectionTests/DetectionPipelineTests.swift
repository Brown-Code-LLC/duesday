import CoreModels
import Foundation
import SubscriptionDetection
import Testing

/// Loads a fixture and runs it through the pipeline.
private func analyze(
    fixture: String,
    ext: String = "txt",
    from: String = "Billing <billing@example.com>",
    subject: String = "Your receipt"
) throws -> DetectionOutcome {
    let url = try #require(Bundle.module.url(
        forResource: fixture,
        withExtension: ext,
        subdirectory: "Fixtures"
    ))
    let content = try String(contentsOf: url, encoding: .utf8)
    let input = EmailMessageInput(
        messageID: "msg-\(fixture)",
        from: from,
        subject: subject,
        date: Date(timeIntervalSince1970: 1_753_000_000),
        plainText: ext == "txt" ? content : nil,
        html: ext == "html" ? content : nil
    )
    return DetectionPipeline.analyze(input)
}

private func requireCandidate(_ outcome: DetectionOutcome) throws -> CandidateDraft {
    guard case .candidate(let draft) = outcome else {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected candidate, got \(outcome)"])
    }
    return draft
}

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar.dateComponents([.year, .month, .day], from: DateComponents(
        calendar: calendar, year: year, month: month, day: dayOfMonth
    ).date ?? .distantPast)
}

private func components(_ date: Date?) -> DateComponents? {
    guard let date else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar.dateComponents([.year, .month, .day], from: date)
}

@Suite("Parser fixtures")
struct ParserFixtureTests {
    @Test("Monthly SaaS receipt extracts amount, cadence, and next date")
    func monthlySaaS() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "monthly-saas",
            from: "Cloudledger <billing@cloudledger.example>",
            subject: "Your Cloudledger receipt"
        ))
        #expect(draft.kind == .receipt)
        #expect(draft.merchantName == "Cloudledger")
        #expect(draft.amount == 24)
        #expect(draft.currencyCode == "USD")
        #expect(draft.frequency == .monthly)
        #expect(components(draft.nextBillingDate) == day(2026, 8, 15))
        #expect(draft.confidence >= 0.7)
        #expect(!draft.evidence.isEmpty)
    }

    @Test("Annual streaming renewal detects the yearly cadence")
    func annualStreaming() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "annual-streaming",
            from: "Streamhaven <no-reply@streamhaven.example>",
            subject: "Your Streamhaven renewal"
        ))
        #expect(draft.frequency == .annual)
        #expect(draft.amount == Decimal(string: "139.99"))
        #expect(components(draft.nextBillingDate) == day(2027, 7, 1))
    }

    @Test("Free-trial warning captures the trial end and conversion price")
    func trialWarning() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "trial-warning",
            from: "Fitloop <hello@fitloop.example>",
            subject: "Your trial is ending"
        ))
        #expect(draft.kind == .trialNotice)
        #expect(components(draft.trialEndDate) == day(2026, 8, 2))
        #expect(draft.amount == Decimal(string: "11.99"))
        #expect(draft.frequency == .monthly)
    }

    @Test("Cancellation confirmation classifies as cancellation with evidence")
    func cancellation() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "cancellation-confirmation",
            from: "Streamhaven <no-reply@streamhaven.example>",
            subject: "Cancellation confirmed"
        ))
        #expect(draft.kind == .cancellation)
        #expect(draft.evidence.contains { $0.field == .cancellation })
    }

    @Test("Failed payment classifies as paymentFailed and keeps the amount")
    func failedPayment() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "failed-payment",
            from: "Notely <billing@notely.example>",
            subject: "Payment failed"
        ))
        #expect(draft.kind == .paymentFailed)
        #expect(draft.amount == Decimal(string: "9.99"))
    }

    @Test("Price-increase notice classifies as priceChange with the new price")
    func priceIncrease() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "price-increase",
            from: "Songbird <no-reply@songbird.example>",
            subject: "Price update"
        ))
        #expect(draft.kind == .priceChange)
        #expect(draft.amount == Decimal(string: "12.99"))
        #expect(draft.evidence.contains { $0.field == .priceChange })
    }

    @Test("Refunds never become candidates")
    func refund() throws {
        let outcome = try analyze(
            fixture: "refund",
            from: "Cloudledger <billing@cloudledger.example>",
            subject: "Refund processed"
        )
        guard case .notSubscription(let reason) = outcome else {
            Issue.record("refund should not create a candidate")
            return
        }
        #expect(reason.lowercased().contains("refund"))
    }

    @Test("Family membership parses like any recurring plan")
    func familyMembership() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "family-membership",
            from: "Fitloop <hello@fitloop.example>",
            subject: "Welcome to Fitloop Family"
        ))
        #expect(draft.amount == Decimal(string: "19.99"))
        #expect(draft.frequency == .monthly)
        #expect(components(draft.nextBillingDate) == day(2026, 8, 20))
    }

    @Test("Variable utility autopay is detected with its current amount")
    func variableUtility() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "variable-utility",
            from: "Lumen Power <statements@lumenpower.example>",
            subject: "Your statement is ready"
        ))
        #expect(draft.amount == Decimal(string: "96.40"))
        #expect(draft.evidence.contains { $0.reason == .recurringPhrase })
    }

    @Test("European decimal-comma EUR amounts parse correctly")
    func eurCurrency() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "eur-currency",
            from: "Journal Lumiere <abo@journallumiere.example>",
            subject: "Votre abonnement"
        ))
        #expect(draft.currencyCode == "EUR")
        #expect(draft.amount == Decimal(string: "11.99"))
        #expect(draft.frequency == .monthly)
    }

    @Test("HTML-only email survives sanitization, entities, and tracking pixels")
    func htmlOnly() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "html-only",
            ext: "html",
            from: "Pixelforge <receipts@pixelforge.example>",
            subject: "Pixelforge receipt"
        ))
        #expect(draft.amount == 18)
        #expect(draft.currencyCode == "USD")
        #expect(draft.frequency == .monthly)
        #expect(components(draft.nextBillingDate) == day(2026, 8, 9))
    }

    @Test("Plain-text receipt parses")
    func plainText() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "plain-text",
            from: "Inkwell Journal <hi@inkwell.example>",
            subject: "Receipt"
        ))
        #expect(draft.amount == 6)
        #expect(draft.frequency == .monthly)
    }

    @Test("Forwarded email still yields the inner receipt's fields")
    func forwarded() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "forwarded",
            from: "Friend <friend@mail.example>",
            subject: "Fwd: Your Notely receipt"
        ))
        #expect(draft.amount == Decimal(string: "9.99"))
        #expect(draft.frequency == .monthly)
        #expect(components(draft.nextBillingDate) == day(2026, 8, 11))
    }

    @Test("Malformed HTML degrades gracefully instead of failing")
    func malformed() throws {
        let draft = try requireCandidate(try analyze(
            fixture: "malformed",
            ext: "html",
            from: "Odd Sender <x@odd.example>",
            subject: "receipt"
        ))
        #expect(draft.amount == Decimal(string: "7.50"))
        #expect(draft.frequency == .monthly)
    }

    @Test("Shipping/marketing mail is rejected as not a subscription")
    func falsePositive() throws {
        let outcome = try analyze(
            fixture: "false-positive",
            from: "Gadget Grove <orders@gadgetgrove.example>",
            subject: "Your order has shipped!"
        )
        guard case .notSubscription = outcome else {
            Issue.record("shipping mail must not create a candidate")
            return
        }
    }

    @Test("Known merchant domains earn trusted-sender evidence")
    func trustedDomain() throws {
        let input = EmailMessageInput(
            messageID: "m-trust",
            from: "Netflix <info@account.netflix.com>",
            subject: "Your Netflix receipt",
            date: nil,
            plainText: "Amount charged: $15.49\nYour subscription renews monthly.",
            html: nil
        )
        let draft = try requireCandidate(DetectionPipeline.analyze(input))
        #expect(draft.merchantName == "Netflix")
        #expect(draft.evidence.contains { $0.reason == .trustedSenderDomain })
        #expect(draft.fieldConfidence["merchant"] == 0.95)
        #expect(draft.confidence >= 0.6)
    }
}

@Suite("Duplicate matching")
struct DuplicateMatcherTests {
    private func draft(
        messageID: String = "m-1",
        merchant: String? = "Cloudledger",
        amount: Decimal? = 24,
        currency: String? = "USD",
        frequency: BillingFrequency? = .monthly
    ) -> CandidateDraft {
        CandidateDraft(
            sourceMessageID: messageID,
            kind: .receipt,
            merchantName: merchant,
            amount: amount,
            currencyCode: currency,
            frequency: frequency,
            customInterval: nil,
            nextBillingDate: nil,
            trialEndDate: nil,
            messageDate: nil,
            evidence: [],
            confidence: 0.8,
            fieldConfidence: [:]
        )
    }

    @Test("Same provider message ID is dropped")
    func sameMessage() {
        let verdict = DuplicateMatcher.evaluate(
            draft: draft(),
            existingCandidates: [.init(sourceMessageID: "m-1", normalizedMerchant: nil, amount: nil, currencyCode: nil)],
            existingSubscriptions: []
        )
        #expect(verdict == .drop(reason: "Message already processed"))
    }

    @Test("Duplicate receipt (same merchant+amount+currency) is dropped")
    func duplicateReceipt() {
        let verdict = DuplicateMatcher.evaluate(
            draft: draft(messageID: "m-2"),
            existingCandidates: [.init(
                sourceMessageID: "m-1",
                normalizedMerchant: "cloudledger",
                amount: 24,
                currencyCode: "USD"
            )],
            existingSubscriptions: []
        )
        guard case .drop = verdict else {
            Issue.record("expected drop")
            return
        }
    }

    @Test("Match against a confirmed subscription links, not drops")
    func existingSubscription() {
        let id = UUID()
        let verdict = DuplicateMatcher.evaluate(
            draft: draft(messageID: "m-3"),
            existingCandidates: [],
            existingSubscriptions: [.init(
                id: id, normalizedMerchant: "cloudledger",
                amount: Decimal(string: "23.75")!, currencyCode: "USD", frequency: .monthly
            )]
        )
        #expect(verdict == .possibleDuplicate(subscriptionID: id))
    }

    @Test("Different currency does not match an existing subscription")
    func currencyMismatch() {
        let verdict = DuplicateMatcher.evaluate(
            draft: draft(messageID: "m-4", currency: "EUR"),
            existingCandidates: [],
            existingSubscriptions: [.init(
                id: UUID(), normalizedMerchant: "cloudledger",
                amount: 24, currencyCode: "USD", frequency: .monthly
            )]
        )
        #expect(verdict == .unique)
    }
}

@Suite("Text extraction primitives")
struct TextPrimitiveTests {
    @Test("Decimal parsing handles both thousand/decimal conventions")
    func decimalConventions() {
        #expect(AmountExtractor.parseDecimal("1,234.56") == Decimal(string: "1234.56"))
        #expect(AmountExtractor.parseDecimal("1.234,56") == Decimal(string: "1234.56"))
        #expect(AmountExtractor.parseDecimal("11,99") == Decimal(string: "11.99"))
        #expect(AmountExtractor.parseDecimal("1,200", noMinor: true) == 1200)
    }

    @Test("HTML extraction drops scripts, styles, and decodes entities")
    func htmlStripping() {
        let html = "<style>.a{}</style><script>x()</script><p>Total: &#36;9.99 &amp; tax</p>"
        let text = HTMLTextExtractor.text(from: html)
        #expect(text.contains("Total: $9.99 & tax"))
        #expect(!text.contains("script"))
        #expect(!text.contains("{"))
    }
}
