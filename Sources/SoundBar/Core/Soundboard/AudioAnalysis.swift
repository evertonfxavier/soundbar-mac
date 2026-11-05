import Foundation

/// How loud a sound is, to bring the sounds of a soundboard to a similar volume.
enum AudioAnalysis {
    /// The average level (RMS) a normalized sound is brought to: about -20 dBFS, a comfortable speech level.
    static let targetRMS: Float = 0.1
    /// The loudest sample a normalized sound may reach, so that boosting a quiet sound never clips it.
    static let peakCeiling: Float = 0.95
    static let minGain: Float = 0.1
    static let maxGain: Float = 8

    /// The factor to multiply the samples by: towards `targetRMS`, but never so that the peak passes `peakCeiling`,
    /// and within `minGain`...`maxGain`. Silence (nothing to measure) is left as it is.
    static func normalizationGain(samples: [Float]) -> Float {
        var peak: Float = 0
        var sum = 0.0
        for sample in samples {
            peak = max(peak, abs(sample))
            sum += Double(sample * sample)
        }
        guard !samples.isEmpty, peak > 0.0001 else { return 1 }
        let rms = Float((sum / Double(samples.count)).squareRoot())
        let wanted = min(targetRMS / max(rms, 0.0001), peakCeiling / peak)
        return max(minGain, min(maxGain, wanted))
    }
}
