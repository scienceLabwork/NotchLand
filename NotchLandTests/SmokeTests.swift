//
//  SmokeTests.swift
//  NotchLandTests
//
//  Verifies the test target links against the app module.
//

import Testing
@testable import NotchLand

struct SmokeTests {
    @Test func smoke() {
        #expect(NotchSettings.Defaults.showNotch == true)
    }
}
