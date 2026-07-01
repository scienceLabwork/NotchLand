//
//  SkyLightWindowBridge.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Best-effort bridge for keeping the notch overlay attached to the correct
//  macOS space. If SkyLight private symbols are unavailable, calls no-op and
//  the panel still relies on its CoreGraphics window level.
//

import AppKit
import Darwin

enum SkyLightWindowSpaceLevel: Int32, CaseIterable {
    case notchSurface = 2_147_483_647
    case lockScreenNotchOverlay = 401
}

@MainActor
final class SkyLightWindowBridge {
    static let shared = SkyLightWindowBridge()

    private typealias MainConnectionIDFunction = @convention(c) () -> Int32
    private typealias SpaceCreateFunction = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevelFunction = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpacesFunction = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpacesFunction = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32?
    private let spaces: [SkyLightWindowSpaceLevel: Int32]
    private let addWindowsAndRemoveFromSpaces: AddWindowsAndRemoveFromSpacesFunction?

    private init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let mainConnectionIDSymbol = dlsym(handle, "SLSMainConnectionID"),
              let spaceCreateSymbol = dlsym(handle, "SLSSpaceCreate"),
              let spaceSetAbsoluteLevelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSpacesSymbol = dlsym(handle, "SLSShowSpaces"),
              let addWindowsAndRemoveFromSpacesSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            connection = nil
            spaces = [:]
            addWindowsAndRemoveFromSpaces = nil
            return
        }

        let mainConnectionID = unsafeBitCast(
            mainConnectionIDSymbol,
            to: MainConnectionIDFunction.self
        )
        let spaceCreate = unsafeBitCast(
            spaceCreateSymbol,
            to: SpaceCreateFunction.self
        )
        let spaceSetAbsoluteLevel = unsafeBitCast(
            spaceSetAbsoluteLevelSymbol,
            to: SpaceSetAbsoluteLevelFunction.self
        )
        let showSpaces = unsafeBitCast(
            showSpacesSymbol,
            to: ShowSpacesFunction.self
        )
        let addWindowsAndRemoveFromSpaces = unsafeBitCast(
            addWindowsAndRemoveFromSpacesSymbol,
            to: AddWindowsAndRemoveFromSpacesFunction.self
        )

        let connection = mainConnectionID()
        var spaces: [SkyLightWindowSpaceLevel: Int32] = [:]

        for level in SkyLightWindowSpaceLevel.allCases {
            let space = spaceCreate(connection, 1, 0)
            guard space != 0 else { continue }

            _ = spaceSetAbsoluteLevel(connection, space, level.rawValue)
            _ = showSpaces(connection, [space] as CFArray)
            spaces[level] = space
        }

        self.connection = connection
        self.spaces = spaces
        self.addWindowsAndRemoveFromSpaces = addWindowsAndRemoveFromSpaces
    }

    func delegateWindow(_ window: NSWindow, to level: SkyLightWindowSpaceLevel) {
        guard let connection,
              let space = spaces[level],
              let addWindowsAndRemoveFromSpaces else {
            return
        }

        _ = addWindowsAndRemoveFromSpaces(
            connection,
            space,
            [window.windowNumber] as CFArray,
            7
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
