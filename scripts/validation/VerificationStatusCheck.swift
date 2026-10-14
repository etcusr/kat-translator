import Foundation

/// Compile with shared/apple/Models/ModelVerificationStatus.swift; no device files are touched.
@main struct VerificationStatusCheck {
    @MainActor static func main() async {
        let status = ModelVerificationStatus.shared
        status.beginRestoration()
        precondition(!status.active, "A cached-only batch must not show the hint")
        for event in [true, false, true, false, true, false] {
            ModelVerificationStatus.changed(event)
            try? await Task.sleep(for: .milliseconds(20))
            precondition(status.active, "The hint must stay visible between files")
        }
        status.endRestoration()
        precondition(!status.active)
        ModelVerificationStatus.changed(true)
        try? await Task.sleep(for: .milliseconds(20))
        precondition(!status.active, "Checks outside startup must not show the startup hint")
        status.beginRestoration()
        precondition(!status.active, "The next batch must start with a clean state")
        status.endRestoration()
        print("PASS: stable hint across three files; cached-only and completed batches stay hidden")
    }
}
