import XCTest
@testable import ActivityCore

final class PhoneInstallTests: XCTestCase {
    func testTeamsFromXcodeDefaults() throws {
        let plist: [String: Any] = [
            "IDEProvisioningTeamByIdentifier": [
                "account-1": [
                    ["teamID": "FREE123456", "teamName": "Diyoz Orozov (Personal Team)", "isFreeProvisioningTeam": true],
                ],
                "account-2": [
                    ["teamID": "PAID654321", "teamName": "Company", "isFreeProvisioningTeam": false],
                ],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let teams = PhoneInstall.teams(xcodeDefaults: data)
        XCTAssertEqual(teams.map(\.id), ["PAID654321", "FREE123456"])
        XCTAssertTrue(teams[1].isFree)
        XCTAssertEqual(PhoneInstall.teams(xcodeDefaults: Data("junk".utf8)), [])

        // A newer Xcode: another key, deeper nesting, no isFree flag.
        let newer: [String: Any] = ["SomeNewAccountsKey": ["accounts": [["teams": [["teamID": "NEW1234567", "teamName": "Diyoz Orozov (Personal Team)"]]]]],
                                    "Unrelated": ["teamID": "not-an-id"]]
        let newerData = try PropertyListSerialization.data(fromPropertyList: newer, format: .xml, options: 0)
        XCTAssertEqual(PhoneInstall.teams(xcodeDefaults: newerData), [PhoneInstall.Team(id: "NEW1234567", name: "Diyoz Orozov (Personal Team)", isFree: true)])
        XCTAssertEqual(PhoneInstall.team(fromCertificateSubject: "subject=UID=ABC, CN=Apple Development: Diyoz Orozov (XYZ), OU=TEAM123456, O=Diyoz Orozov, C=US"), "TEAM123456")
        XCTAssertEqual(PhoneInstall.team(fromCertificateSubject: "subject= /UID=X/CN=Apple Development/OU=AB12CD34EF/O=X"), "AB12CD34EF")
        XCTAssertNil(PhoneInstall.team(fromCertificateSubject: "CN=nothing"))
        XCTAssertEqual(PhoneInstall.bundleID(team: "FREE123456"), "com.iopew.ActivityPhone.FREE123456")
        XCTAssertEqual(PhoneInstall.bundleID(team: "AB/../C"), "com.iopew.ActivityPhone.ABC")
    }

    func testDevicesFromDevicectl() {
        let json = """
        {"result": {"devices": [
          {"identifier": "watch", "hardwareProperties": {"platform": "iOS", "deviceType": "appleWatch", "udid": "w"},
           "connectionProperties": {"pairingState": "paired", "tunnelState": "disconnected"}, "deviceProperties": {"name": "Watch"}},
          {"identifier": "wifi-phone", "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone", "udid": "u1"},
           "connectionProperties": {"pairingState": "paired", "tunnelState": "disconnected", "transportType": "localNetwork"},
           "deviceProperties": {"name": "Old iPhone", "developerModeStatus": "disabled"}},
          {"identifier": "cable-phone", "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone", "udid": "u2"},
           "connectionProperties": {"pairingState": "paired", "tunnelState": "connected", "transportType": "wired"},
           "deviceProperties": {"name": "iPhone 13 Pro", "developerModeStatus": "enabled"}},
          {"identifier": "gone", "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone", "udid": "u3"},
           "connectionProperties": {"pairingState": "paired", "tunnelState": "unavailable"}, "deviceProperties": {"name": "Gone"}},
          {"identifier": "mac", "hardwareProperties": {"platform": "macOS", "udid": "m"},
           "connectionProperties": {"pairingState": "paired"}, "deviceProperties": {"name": "Mac"}}
        ]}}
        """
        let devices = PhoneInstall.devices(devicectlJSON: Data(json.utf8))
        XCTAssertEqual(devices.map(\.identifier), ["cable-phone", "wifi-phone"])
        XCTAssertEqual(devices[0].udid, "u2")
        XCTAssertTrue(devices[0].developerModeEnabled)
        XCTAssertFalse(devices[1].developerModeEnabled)
        XCTAssertEqual(PhoneInstall.devices(devicectlJSON: Data()), [])
    }

    func testBuildLogErrors() {
        let log = """
        CompileSwift normal arm64
        /x/MacView.swift:10:5: error: cannot find 'foo' in scope
        /x/MacView.swift:10:5: error: cannot find 'foo' in scope
        error: No Account for Team "ABC". Add a new account in Accounts settings.
        ** BUILD FAILED **
        """
        XCTAssertEqual(PhoneInstall.errors(inBuildLog: log),
                       ["cannot find 'foo' in scope", "No Account for Team \"ABC\". Add a new account in Accounts settings."])
    }
}
