/// Presentation is independent of the recording workflow's lifetime: finishing
/// remains true while automatic speech plays, after text is already available.
public enum VoiceResultVisibility {
    public static func shouldShow(hasOriginal: Bool, hasTranslation: Bool, capturing: Bool,
                                  finishing: Bool, processing: Bool, preview: Bool, alreadyShown: Bool) -> Bool {
        guard !capturing, hasOriginal || hasTranslation else { return false }
        if alreadyShown { return true }
        if processing { return !preview && hasTranslation }
        // Do not flash the previous recording while stop/normalization is pending.
        return !finishing
    }
}
