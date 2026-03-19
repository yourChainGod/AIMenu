import XCTest
@testable import AIMenu

final class AppSettingsCodableTests: XCTestCase {
    func testDecodeLegacySettingsWithoutAutoSmartSwitchUsesDefault() throws {
        let json = """
        {
          "launchAtStartup": true,
          "trayUsageDisplayMode": "remaining",
          "launchCodexAfterSwitch": true,
          "syncOpencodeOpenaiAuth": false,
          "restartEditorsOnSwitch": false,
          "restartEditorTargets": [],
          "autoStartApiProxy": true,
          "remoteServers": [],
          "locale": "en"
        }
        """

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.autoSmartSwitch, false)
        XCTAssertEqual(decoded.autoStartApiProxy, true)
        XCTAssertEqual(decoded.locale, AppLocale.english.identifier)
    }
}
