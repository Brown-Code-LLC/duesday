import CoreModels
import FeatureDetectionReview
import Foundation
import Persistence
import SwiftData
import Testing

@MainActor
@Suite("Candidate review actions", .serialized)
struct CandidateReviewServiceTests {
    private func completeCandidate(
        confidence: Double = 0.9,
        merchant: String = "Cloudledger"
    ) -> DetectionCandidate {
        DetectionCandidate(
            sourceMessageID: UUID().uuidString,
            merchantName: merchant,
            amount: 24,
            currencyCode: "USD",
            billingFrequency: .monthly,
            nextBillingDate: Date(timeIntervalSince1970: 2_000_000_000),
            confidenceScore: confidence
        )
    }

    @Test("Confirm creates exactly one detected subscription and resolves the candidate")
    func confirm() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext
        let candidate = completeCandidate()
        context.insert(candidate)

        let result = try CandidateReviewService(context: context).confirm(candidate)
        let created = try #require(result)

        #expect(created.detectionSource == .gmail)
        #expect(created.confidence == 0.9)
        #expect(created.merchantName == "Cloudledger")
        #expect(candidate.reviewStatus == .confirmed)
        #expect(try context.fetchCount(FetchDescriptor<Subscription>()) == 1)
    }

    @Test("Incomplete candidates cannot be confirmed and remain pending")
    func incomplete() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext
        let candidate = DetectionCandidate(
            merchantName: "Unknown Plan",
            confidenceScore: 0.95
        )
        context.insert(candidate)

        let created = try CandidateReviewService(context: context).confirm(candidate)

        #expect(created == nil)
        #expect(candidate.reviewStatus == .pending)
        #expect(try context.fetchCount(FetchDescriptor<Subscription>()) == 0)
    }

    @Test("Bulk confirm accepts only complete high-confidence candidates")
    func bulkConfirm() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext
        let eligible = completeCandidate()
        let lowConfidence = completeCandidate(confidence: 0.84, merchant: "Possible Plan")
        let incomplete = DetectionCandidate(merchantName: "Missing Price", confidenceScore: 0.99)
        [eligible, lowConfidence, incomplete].forEach(context.insert)

        let count = try CandidateReviewService(context: context)
            .bulkConfirm([eligible, lowConfidence, incomplete])

        #expect(count == 1)
        #expect(eligible.reviewStatus == .confirmed)
        #expect(lowConfidence.reviewStatus == .pending)
        #expect(incomplete.reviewStatus == .pending)
        #expect(try context.fetchCount(FetchDescriptor<Subscription>()) == 1)
    }

    @Test("Merge updates the existing entry without creating a duplicate")
    func merge() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext
        let oldDate = Date(timeIntervalSince1970: 1_900_000_000)
        let newDate = Date(timeIntervalSince1970: 2_000_000_000)
        let subscription = Subscription(
            merchantName: "Cloudledger",
            amount: 20,
            currencyCode: "USD",
            billingFrequency: .monthly,
            nextBillingDate: oldDate
        )
        let candidate = DetectionCandidate(
            merchantName: "Cloudledger",
            amount: 24,
            currencyCode: "USD",
            billingFrequency: .monthly,
            nextBillingDate: newDate,
            confidenceScore: 0.9
        )
        context.insert(subscription)
        context.insert(candidate)

        try CandidateReviewService(context: context).merge(candidate, into: subscription)

        #expect(subscription.amount == 24)
        #expect(subscription.lastBillingDate == oldDate)
        #expect(subscription.nextBillingDate == newDate)
        #expect(candidate.reviewStatus == .merged)
        #expect(try context.fetchCount(FetchDescriptor<Subscription>()) == 1)
    }

    @Test("Ignore and reject preserve negative decisions")
    func negativeDecisions() throws {
        let controller = try PersistenceController(inMemory: true)
        let context = controller.mainContext
        let ignored = completeCandidate(merchant: "Ignored")
        let rejected = completeCandidate(merchant: "Rejected")
        context.insert(ignored)
        context.insert(rejected)
        let service = CandidateReviewService(context: context)

        try service.ignore(ignored)
        try service.reject(rejected)

        #expect(ignored.reviewStatus == .ignored)
        #expect(rejected.reviewStatus == .rejected)
    }
}
