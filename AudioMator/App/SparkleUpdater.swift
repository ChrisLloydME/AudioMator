#if os(macOS) && ENABLE_SPARKLE_UPDATES
import Sparkle

final class SparkleUpdater {
    static let shared = SparkleUpdater()

    let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
#endif
