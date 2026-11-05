import Foundation
import Testing

@Suite("AudioAnalysis")
struct AudioAnalysisTests {
    private func constant(_ value: Float, count: Int = 1000) -> [Float] { [Float](repeating: value, count: count) }

    @Test("a quiet sound is raised towards the target level")
    func raisesQuiet() {
        let gain = AudioAnalysis.normalizationGain(samples: constant(0.05))
        #expect(abs(gain - 2) < 0.001)  // 0.1 / 0.05
    }

    @Test("a loud sound is lowered")
    func lowersLoud() {
        let gain = AudioAnalysis.normalizationGain(samples: constant(0.5))
        #expect(abs(gain - 0.2) < 0.001)  // 0.1 / 0.5
    }

    @Test("a boost never takes the peak past the ceiling")
    func respectsPeak() {
        // a quiet average with one high peak: the level wants a big boost, the peak allows only a little
        var samples = constant(0.01)
        samples[0] = 0.5
        let gain = AudioAnalysis.normalizationGain(samples: samples)
        #expect(gain <= AudioAnalysis.peakCeiling / 0.5 + 0.0001)
        #expect(0.5 * gain <= AudioAnalysis.peakCeiling + 0.0001)
    }

    @Test("the gain stays within its limits")
    func clamped() {
        #expect(AudioAnalysis.normalizationGain(samples: constant(0.0002)) <= AudioAnalysis.maxGain)
        #expect(AudioAnalysis.normalizationGain(samples: constant(1)) >= AudioAnalysis.minGain)
    }

    @Test("silence, or nothing, is left as it is")
    func silence() {
        #expect(AudioAnalysis.normalizationGain(samples: []) == 1)
        #expect(AudioAnalysis.normalizationGain(samples: constant(0)) == 1)
    }

    @Test("two sounds of very different loudness come out close after normalizing")
    func evensOut() {
        let quiet = AudioAnalysis.normalizationGain(samples: constant(0.04)) * 0.04
        let loud = AudioAnalysis.normalizationGain(samples: constant(0.4)) * 0.4
        #expect(abs(quiet - loud) < 0.001)
    }
}
