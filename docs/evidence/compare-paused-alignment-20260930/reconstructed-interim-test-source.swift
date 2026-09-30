    func testPausedAlignmentAndSeekIgnoreSimulatedDelayedMPVPlayingObservation() async throws {
        let fixtures = try fixtureDirectory()
        let tolerance = 1.0 / 24.0
        try await exercisePreparedPair(
            primaryURL: fixtures.appending(path: "compare/source-a.mov"),
            secondaryURL: fixtures.appending(path: "compare/source-b.mov"),
            primaryBackend: .mpv,
            secondaryBackend: .mpv,
            seekTarget: 2, tolerance: tolerance,
            description: "delayed primary pause observation"
        ) { primary, secondary, session in
            session.pause(primary: primary)
            session.seek(primary: primary, to: 2)
            let settled = await self.waitUntil {
                !primary.isPlaying && !secondary.isPlaying
                    && abs(primary.playbackTimeSnapshot() - 2) <= tolerance
                    && abs(secondary.playbackTimeSnapshot() - 3) <= tolerance
            }
            XCTAssertTrue(settled)
            let primaryMPV = try XCTUnwrap(primary.mpvPlayer)
            XCTAssertEqual(primaryMPV.playbackTimeSnapshot() ?? -1, 2, accuracy: tolerance)

            var secondaryResumed = false
            let observation = secondary.$isPlaying.sink { playing in
                if playing { secondaryResumed = true }
            }
            defer { observation.cancel() }
            // Both real backends are paused. readEvents publishes a previously
            // captured MPV pause value asynchronously on the main queue; this
            // cached flag has no setter that changes libmpv's actual pause.
            // Simulate its brief lag after an explicit Pause, without sending
            // Play to A or adding a production test hook.
            primaryMPV.isPlaying = true
            primary.syncIsPlaying()
            session.setManualOffset(0.5, primary: primary)
            session.seek(primary: primary, to: 2)
            primaryMPV.isPlaying = false
            primary.syncIsPlaying()

            try await Task.sleep(for: .milliseconds(500))
            XCTAssertFalse(secondaryResumed,
                           "A delayed playing observation must not override explicit Pause.")
            XCTAssertFalse(secondary.isPlaying)
            XCTAssertEqual(secondary.playbackTimeSnapshot(), 2.5, accuracy: tolerance)
            XCTAssertEqual(primary.playbackTimeSnapshot(), 2, accuracy: tolerance,
                           "Changing an observed cache must leave A's decoder paused.")

            session.play(primary: primary)
            let resumed = await self.waitUntil { primary.isPlaying && secondary.isPlaying }
            XCTAssertTrue(resumed, "An explicit Play must still resume both sources.")
            session.pause(primary: primary)

            let pausedAgain = await self.waitUntil { !primary.isPlaying && !secondary.isPlaying }
            XCTAssertTrue(pausedAgain)
            let primaryPreparation = primary.preparationID
            let secondaryPreparation = secondary.preparationID
            secondaryResumed = false
            primaryMPV.isPlaying = true
            primary.syncIsPlaying()
            session.reload(primary: primary)
            try await self.attachRenderSurface(to: primary)
            try await self.attachRenderSurface(to: secondary)
            let reloaded = await self.waitUntil {
                primary.preparationID > primaryPreparation
                    && secondary.preparationID > secondaryPreparation
                    && primary.isReady && secondary.isReady
            }
            XCTAssertTrue(reloaded)
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertFalse(secondaryResumed,
                           "Reload must not capture a delayed observation as resume intent.")
            XCTAssertFalse(primary.isPlaying)
            XCTAssertFalse(secondary.isPlaying)

            session.slowForward(primary: primary)
            let shuttleResumed = await self.waitUntil { primary.isPlaying && secondary.isPlaying }
            XCTAssertTrue(shuttleResumed, "Explicit shuttle must clear the Pause intent.")
            session.pause(primary: primary)
        }
    }

