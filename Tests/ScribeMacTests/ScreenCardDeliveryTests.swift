import Testing
@testable import ScribeMac

@Suite struct ScreenCardDeliveryTests {
    @Test func acceptsCardCompletedBeforeOrWithinReleaseDeadline() {
        let release = ContinuousClock.now
        for completion in [release.advanced(by: .seconds(-1)), release, release.advanced(by: .milliseconds(1_500))] {
            var delivery = ScreenCardDelivery()
            delivery.fallback = "names and nearby text"
            delivery.termsFinished = true
            delivery.finish("summary", at: completion)
            delivery.release(at: release)
            #expect(delivery.result == "summary")
            #expect(!delivery.shouldWait(at: release))
        }
    }

    @Test func lateCardCannotWinEvenIfSpeechFinishesMuchLater() {
        let release = ContinuousClock.now
        var delivery = ScreenCardDelivery()
        delivery.fallback = "names and nearby text"
        delivery.release(at: release)
        #expect(delivery.shouldWait(at: release.advanced(by: .seconds(1))))
        #expect(!delivery.shouldWait(at: release.advanced(by: .milliseconds(1_500))))
        delivery.finish("too late", at: release.advanced(by: .milliseconds(1_501)))
        #expect(delivery.result == "names and nearby text")
        delivery.release(at: release.advanced(by: .seconds(20)))
        #expect(delivery.result == "names and nearby text")
    }

    @Test func modelFailureStillAllowsTermsToReachFallbackUntilDeadline() {
        let release = ContinuousClock.now
        var delivery = ScreenCardDelivery()
        delivery.release(at: release)
        delivery.finish(nil, at: release)
        #expect(delivery.shouldWait(at: release))
        delivery.fallback = "extracted names and cursor text"
        delivery.termsFinished = true
        #expect(!delivery.shouldWait(at: release))
        #expect(delivery.result == "extracted names and cursor text")
    }
}
