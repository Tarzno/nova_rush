import Foundation

extension Bundle {
    /// The package resource bundle, located robustly.
    ///
    /// The `Bundle.module` accessor SwiftPM generates for *executable* targets
    /// checks only two places: `<Bundle.main.bundleURL>/<name>.bundle` — the
    /// .app *root*, not `Contents/Resources` where build-app.sh puts it — and
    /// an absolute path into this checkout's `.build` directory. An installed
    /// .app therefore resolves its resources through the build directory, and
    /// traps on any machine that doesn't have this checkout. Look in the app's
    /// `Contents/Resources` first (this also covers `swift run`, where
    /// `resourceURL` is the executable's directory); keep `Bundle.module` as
    /// the fallback.
    static let resources: Bundle = {
        let name = "NovaRush_NovaRush.bundle"
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}
