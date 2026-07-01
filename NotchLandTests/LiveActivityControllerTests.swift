//
//  LiveActivityControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct LiveActivityControllerTests {
    private func makeController() -> LiveActivityController {
        LiveActivityController(settings: NotchSettings())
    }

    @Test func newestActivityWins() {
        let c = makeController()
        c.post(LiveActivity(kind: .download(fileName: "x.zip"), title: "Copied", detail: nil, progress: nil))
        c.post(LiveActivity(kind: .timer(remaining: 60), title: "Timer", detail: "1:00", progress: 0.5))
        #expect(c.current?.title == "Timer")
    }

    @Test func endingCurrentRevealsNothing() {
        let c = makeController()
        let activity = LiveActivity(kind: .download(fileName: "x.zip"), title: "Copied", detail: nil, progress: nil)
        c.post(activity)
        c.end(activity.id)
        #expect(c.current == nil)
    }

    @Test func endingStaleIdKeepsCurrent() {
        let c = makeController()
        let old = LiveActivity(kind: .download(fileName: "x.zip"), title: "Old", detail: nil, progress: nil)
        c.post(old)
        let new = LiveActivity(kind: .download(fileName: "x.zip"), title: "New", detail: nil, progress: nil)
        c.post(new)
        c.end(old.id)
        #expect(c.current?.title == "New")
    }

    @Test func updateReplacesInPlace() {
        let c = makeController()
        var activity = LiveActivity(kind: .download(fileName: "x.zip"), title: "x.zip", detail: nil, progress: 0.1)
        c.post(activity)
        activity.progress = 0.9
        c.post(activity)
        #expect(c.current?.progress == 0.9)
    }

    @Test func disabledSettingDropsPosts() {
        let settings = NotchSettings()
        let previous = settings.liveActivitiesEnabled
        defer { settings.liveActivitiesEnabled = previous }
        settings.liveActivitiesEnabled = false
        let c = LiveActivityController(settings: settings)
        c.post(LiveActivity(kind: .download(fileName: "x.zip"), title: "Copied", detail: nil, progress: nil))
        #expect(c.current == nil)
    }
}
