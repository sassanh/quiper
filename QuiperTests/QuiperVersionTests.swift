import Foundation
import Testing
@testable import Quiper

struct QuiperVersionTests {
    @Test func numericComponentsOrderNumerically() {
        #expect(QuiperVersion.isAfter("1.3.3", than: "1.2.3"))
        #expect(QuiperVersion.isAfter("2.2.3", than: "1.2.3"))
        #expect(!QuiperVersion.isAfter("1.2.3", than: "1.2.3"))
        #expect(QuiperVersion.isAtLeast("1.2.3", "1.2.3") == true)
        #expect(QuiperVersion.compare("1.2", to: "1.2.0") == .orderedSame)
    }

    @Test func anySuffixOrdersAfterUnsuffixedVersion() {
        #expect(QuiperVersion.isAfter("1.2.3-beta-nonproduction", than: "1.2.3"))
        #expect(QuiperVersion.isAfter("1.2.3-whatever", than: "1.2.3"))
        #expect(QuiperVersion.isAtLeast("1.2.3-whatever", "1.2.3") == true)
        #expect(QuiperVersion.isAtLeast("1.2.3", "1.2.3-whatever") == false)
        #expect(
            QuiperVersion.compare(
                "1.2.3",
                to: "1.2.3-beta-nonproduction"
            ) == .orderedAscending
        )
    }

    @Test func buildNumberOrdersVersionsWithinSameSuffixTier() {
        #expect(
            QuiperVersion.isAfter(
                "1.2.3-whatever (10)",
                than: "1.2.3-whatever (9)"
            )
        )
        #expect(
            QuiperVersion.compare(
                "1.2.3-whatever (9)",
                to: "1.2.3-whatever (10)"
            ) == .orderedAscending
        )
        #expect(QuiperVersion.isAfter("1.2.3 (10)", than: "1.2.3 (9)"))
    }

    @Test func suffixTierTakesPrecedenceOverBuildNumber() {
        #expect(
            QuiperVersion.isAfter(
                "1.2.3-whatever (9)",
                than: "1.2.3 (10)"
            )
        )
        #expect(
            QuiperVersion.isAtLeast(
                "1.2.3 (10)",
                "1.2.3-whatever (9)"
            ) == false
        )
    }

    @Test func olderBuildIsNotAtLeastNewerBuild() {
        #expect(
            QuiperVersion.isAtLeast(
                "1.2.3-whatever (9)",
                "1.2.3-whatever (10)"
            ) == false
        )
        #expect(
            QuiperVersion.isAfter(
                "1.2.3-whatever (1)",
                than: "1.2.3-whatever"
            )
        )
    }

    @Test func suffixLabelsShareOneOrderingTier() {
        #expect(
            QuiperVersion.compare(
                "1.2.3-beta-nonproduction (10)",
                to: "1.2.3-whatever (10)"
            ) == .orderedSame
        )
    }

    @Test func suffixLabelsWithoutBuildMetadataRemainUnordered() {
        #expect(
            QuiperVersion.compare(
                "1.2.3-beta",
                to: "1.2.3-nightly"
            ) == nil
        )
        #expect(
            QuiperVersion.compare(
                "1.2.3-beta-nonproduction",
                to: "1.2.3-beta"
            ) == .orderedSame
        )
    }

    @Test func releaseTagsAndDisplayVersionsUseSameOrdering() {
        #expect(
            QuiperVersion.isAfter(
                "beta-v1.2.3-10",
                buildNumber: 10,
                than: "1.2.3-beta-nonproduction",
                buildNumber: 9
            )
        )
        #expect(
            QuiperVersion.compare(
                "v1.3.3",
                buildNumber: 11,
                to: "1.2.3-whatever (10)"
            ) == .orderedDescending
        )
        #expect(
            QuiperVersion.isAfter(
                "nightly-v4.4.1-824",
                buildNumber: 824,
                than: "4.4.1-nightly-nonproduction (823)"
            )
        )
        #expect(
            QuiperVersion.isAfter(
                "v4.5.0",
                buildNumber: 827,
                than: "4.4.1-beta-nonproduction (826)"
            )
        )
        #expect(
            QuiperVersion.isAfter(
                "beta--v3.3.0-621-623",
                buildNumber: 623,
                than: "3.3.0-beta-nonproduction (622)"
            )
        )
    }

    @Test func explicitBuildNumbersProvideFallbackForLegacyTags() {
        #expect(
            QuiperVersion.compare(
                "beta",
                buildNumber: 10,
                to: "nightly",
                buildNumber: 9
            ) == .orderedDescending
        )
        #expect(QuiperVersion.compare("invalid", to: "also-invalid") == nil)
    }

    @Test func representativeVersionsMaintainStrictOrdering() {
        let versions = [
            "1.2.3",
            "1.2.3 (9)",
            "1.2.3 (10)",
            "1.2.3-whatever",
            "1.2.3-whatever (9)",
            "1.2.3-whatever (10)",
            "1.3.3",
            "2.2.3",
        ]

        for lowerIndex in versions.indices {
            for higherIndex in versions.indices where higherIndex > lowerIndex {
                #expect(
                    QuiperVersion.compare(
                        versions[lowerIndex],
                        to: versions[higherIndex]
                    ) == .orderedAscending
                )
                #expect(
                    QuiperVersion.compare(
                        versions[higherIndex],
                        to: versions[lowerIndex]
                    ) == .orderedDescending
                )
            }
        }
    }
}
