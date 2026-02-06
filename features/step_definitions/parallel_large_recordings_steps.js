import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object:
// this.recordingFiles - array of paths to the generated recording files
// this.sessions - array of session objects with {recording, hashIndex, playerState, hashes}
// this.sessionResults - array of {sessionId, requests: [{hash, result, error, duration}], totalDuration}
// this.testError - any error that occurred during the test setup

/**
 * Generate a large recording file with the specified size.
 * Creates request/response pairs with enough payload to reach the target size.
 *
 * @param {string} filePath - The path to write the recording (will be compressed)
 * @param {number} pairCount - Number of request/response pairs to include
 * @param {number} targetSizeMB - Target total size in megabytes (uncompressed)
 * @param {string} sessionId - Unique identifier for this recording session
 * @returns {Promise<{hashes: string[], uncompressedSize: number, compressedSize: number}>}
 */
async function generateLargeRecordingForSession(
  filePath,
  pairCount,
  targetSizeMB,
  sessionId,
) {
  const targetSizeBytes = targetSizeMB * 1024 * 1024;
  // Account for both request and response messages
  const bytesPerPair = Math.floor(targetSizeBytes / pairCount);
  const bytesPerMessage = Math.floor(bytesPerPair / 2);

  // Base message structure overhead (approximate JSON size without payload)
  const baseMessageSize = 600;
  const paddingSize = Math.max(0, bytesPerMessage - baseMessageSize);

  const timestamp = new Date().toISOString();
  const hashes = [];

  const recording = {
    schemaVersion: 2,
    scenarioName: `parallel-session-${sessionId}`,
    recordedAt: timestamp,
    messages: [],
  };

  for (let i = 0; i < pairCount; i++) {
    // Create unique hash for this session and message
    const hash = `session_${sessionId}_hash_${i.toString(16).padStart(12, "0")}`;
    hashes.push(hash);

    const streamId = `stream-${sessionId}-${i}`;
    const traceId = `trace-${sessionId}-${i}`;

    // Create a request message (command from client to harness)
    const requestMessage = {
      envelope: {
        streamId: streamId,
        traceId: traceId,
        causationStreamId: null,
        parentStreamId: null,
        siblingIndex: 0,
        eventSeq: i * 2,
        timestamp: timestamp,
        channel: "program",
        payloadHash: null,
        payload: {
          kind: "command",
          data: {
            type: "open",
            payload: {
              service: "http",
              payload: {
                method: "GET",
                url: `https://example.com/api/session/${sessionId}/resource/${i}`,
                headers: {
                  "Content-Type": "application/json",
                  "X-Request-Id": `req-${sessionId}-${i.toString(16).padStart(8, "0")}`,
                  "X-Session-Id": sessionId,
                },
                // Add padding to reach target size
                body: `session_${sessionId}_request_data_${i}_`.padEnd(
                  paddingSize,
                  "x",
                ),
              },
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "to_harness",
      hash: hash,
    };

    // Create a corresponding response message
    const responseMessage = {
      envelope: {
        streamId: streamId,
        traceId: traceId,
        causationStreamId: null,
        parentStreamId: null,
        siblingIndex: 0,
        eventSeq: i * 2 + 1,
        timestamp: timestamp,
        channel: "program",
        payloadHash: null,
        payload: {
          kind: "event",
          data: {
            type: "close",
            payload: {
              service: "http",
              payload: {
                status: 200,
                headers: {
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  success: true,
                  sessionId: sessionId,
                  requestIndex: i,
                  // Add padding to reach target size
                  data: `session_${sessionId}_response_data_${i}_`.padEnd(
                    Math.floor(paddingSize / 2),
                    "y",
                  ),
                }),
              },
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "from_harness",
      hash: null,
    };

    recording.messages.push(requestMessage);
    recording.messages.push(responseMessage);
  }

  // Convert to JSON
  const jsonContent = JSON.stringify(recording, null, 2);
  const uncompressedSize = Buffer.byteLength(jsonContent, "utf8");

  // Compress using zstd
  const zstd = await import("zstd-napi");
  const uncompressedBuffer = Buffer.from(jsonContent, "utf8");
  const compressedBuffer = zstd.compress(uncompressedBuffer);

  // Write compressed file
  await fs.writeFile(filePath, compressedBuffer);
  const compressedSize = compressedBuffer.length;

  return { hashes, uncompressedSize, compressedSize };
}

Given(
  "{int} separate recording files of approximately {int}MB each",
  async function (fileCount, sizeMB) {
    // Create temp workspace for test files
    await this.createTempWorkspace();

    this.recordingFiles = [];
    this.recordingSizes = [];
    this.sessionHashes = [];
    this.testError = null;

    // Number of request/response pairs per recording
    // More pairs = more messages to index, which tests the chunked processing
    const pairsPerRecording = 100;

    console.log(
      `    Generating ${fileCount} recording files of ~${sizeMB}MB each...`,
    );

    for (let i = 0; i < fileCount; i++) {
      const sessionId = `s${i}`;
      const filePath = path.join(
        this.workspace,
        `parallel-session-${sessionId}.json.zstd`,
      );

      try {
        const { hashes, uncompressedSize, compressedSize } =
          await generateLargeRecordingForSession(
            filePath,
            pairsPerRecording,
            sizeMB,
            sessionId,
          );

        this.recordingFiles.push(filePath);
        this.sessionHashes.push(hashes);
        this.recordingSizes.push({
          sessionId,
          uncompressedMB: uncompressedSize / (1024 * 1024),
          compressedMB: compressedSize / (1024 * 1024),
        });

        // Verify file was created
        const exists = await this.fileExists(filePath);
        assert(exists, `Recording file was not created at: ${filePath}`);
      } catch (err) {
        this.testError = err;
        return;
      }
    }

    console.log(
      `    Generated ${fileCount} recordings: ${this.recordingSizes.map((s) => `${s.sessionId}: ${s.uncompressedMB.toFixed(1)}MB`).join(", ")}`,
    );

    // Store expected values for later assertions
    this.expectedFileCount = fileCount;
    this.expectedSizeMB = sizeMB;
    this.pairsPerRecording = pairsPerRecording;
  },
);

When(
  "{int} playback sessions are started simultaneously",
  async function (sessionCount) {
    // Skip if file generation failed
    if (this.testError) {
      return;
    }

    // Verify we have the expected number of recording files
    if (this.recordingFiles.length !== sessionCount) {
      this.testError = new Error(
        `Expected ${sessionCount} recording files, but only have ${this.recordingFiles.length}`,
      );
      return;
    }

    // Import the necessary modules
    let Recording, Player;
    try {
      Recording = await import("../../output/Replay.Recording/index.js");
      Player = await import("../../output/Replay.Player/index.js");
    } catch (err) {
      if (err.code === "ERR_MODULE_NOT_FOUND") {
        this.testError = new Error(
          `Module not found: ${err.message} - ensure PureScript is compiled`,
        );
        return;
      }
      throw err;
    }

    // Check for required functions
    if (typeof Recording.loadRecordingLazyJs !== "function") {
      this.testError = new Error(
        "loadRecordingLazyJs function not implemented yet - test is pending implementation",
      );
      return;
    }

    if (typeof Recording.buildHashIndexChunkedJs !== "function") {
      this.testError = new Error(
        "buildHashIndexChunkedJs function not implemented yet - test is pending implementation",
      );
      return;
    }

    if (
      typeof Player.createLazyPlayerStateJs !== "function" &&
      typeof Player.createLazyPlayerState !== "function"
    ) {
      this.testError = new Error(
        "createLazyPlayerState(Js) function not implemented yet - test is pending implementation",
      );
      return;
    }

    this.sessions = [];
    console.log(`    Starting ${sessionCount} parallel loading sessions...`);

    // Track total loading time to verify parallel efficiency
    const loadingStartTime = Date.now();

    // Start all sessions simultaneously (in parallel)
    // This is the key test - all sessions should be able to load their recordings
    // concurrently without blocking each other
    const sessionPromises = this.recordingFiles.map(async (filePath, index) => {
      const sessionId = `s${index}`;
      const sessionStartTime = Date.now();

      try {
        // Step 1: Load recording lazily
        const loadResult = await Recording.loadRecordingLazyJs(filePath)();

        // Handle Either type
        let lazyRecording;
        if (loadResult && typeof loadResult === "object") {
          if (
            "value0" in loadResult &&
            loadResult.constructor?.name === "Left"
          ) {
            throw new Error(`Loading failed: ${loadResult.value0}`);
          }
          if (
            "value0" in loadResult &&
            loadResult.constructor?.name === "Right"
          ) {
            lazyRecording = loadResult.value0;
          } else {
            lazyRecording = loadResult;
          }
        } else {
          lazyRecording = loadResult;
        }

        // Step 2: Build hash index (chunked, non-blocking)
        const buildFunc =
          Recording.buildHashIndexChunkedJs || Recording.buildHashIndexChunked;
        let hashIndex;

        const buildResult = buildFunc(lazyRecording);
        if (typeof buildResult === "function") {
          hashIndex = await buildResult();
        } else if (
          buildResult instanceof Promise ||
          (buildResult && typeof buildResult.then === "function")
        ) {
          hashIndex = await buildResult;
        } else {
          hashIndex = buildResult;
        }

        // Step 3: Create player state
        const createPlayerFunc =
          Player.createLazyPlayerStateJs || Player.createLazyPlayerState;
        let playerState;

        const playerStateResult = createPlayerFunc(lazyRecording)(hashIndex);
        if (typeof playerStateResult === "function") {
          playerState = playerStateResult();
        } else {
          playerState = playerStateResult;
        }

        const loadDuration = Date.now() - sessionStartTime;

        return {
          sessionId,
          filePath,
          lazyRecording,
          hashIndex,
          playerState,
          hashes: this.sessionHashes[index],
          loadDuration,
          error: null,
        };
      } catch (err) {
        return {
          sessionId,
          filePath,
          lazyRecording: null,
          hashIndex: null,
          playerState: null,
          hashes: this.sessionHashes[index],
          loadDuration: Date.now() - sessionStartTime,
          error: err,
        };
      }
    });

    // Wait for all sessions to complete
    this.sessions = await Promise.all(sessionPromises);

    const totalLoadingTime = Date.now() - loadingStartTime;

    // Check for any loading errors
    const failedSessions = this.sessions.filter((s) => s.error !== null);
    if (failedSessions.length > 0) {
      const errors = failedSessions
        .map((s) => `Session ${s.sessionId}: ${s.error.message}`)
        .join("\n");
      this.testError = new Error(
        `${failedSessions.length} of ${sessionCount} sessions failed to load:\n${errors}`,
      );
      return;
    }

    console.log(
      `    All ${sessionCount} sessions loaded in ${totalLoadingTime}ms total. ` +
        `Individual times: ${this.sessions.map((s) => `${s.sessionId}: ${s.loadDuration}ms`).join(", ")}`,
    );

    // Store for later use
    this.Player = Player;
  },
);

When(
  "each session makes {int} requests within {int} seconds",
  async function (requestCount, timeoutSeconds) {
    // Skip if previous steps failed
    if (this.testError) {
      return;
    }

    if (!this.sessions || this.sessions.length === 0) {
      this.testError = new Error("No sessions available for requests");
      return;
    }

    const timeoutMs = timeoutSeconds * 1000;
    this.sessionResults = [];

    console.log(
      `    Each of ${this.sessions.length} sessions making ${requestCount} requests (timeout: ${timeoutSeconds}s)...`,
    );

    // Create a promise for each session's request sequence
    const sessionRequestPromises = this.sessions.map(async (session) => {
      const sessionStartTime = Date.now();
      const requests = [];

      // Each session makes its requests
      for (let i = 0; i < requestCount; i++) {
        const requestStartTime = Date.now();

        // Pick a hash to look up (use modulo to cycle through available hashes)
        const hashIndex = i % session.hashes.length;
        const targetHash = session.hashes[hashIndex];

        try {
          // Use findMatchLazy to find the matching message
          const findFunc =
            this.Player.findMatchLazyJs || this.Player.findMatchLazy;
          const findResult = findFunc(targetHash)(session.playerState);

          // Handle Effect return type
          let matchResult;
          if (typeof findResult === "function") {
            matchResult = findResult();
          } else {
            matchResult = findResult;
          }

          // Handle Maybe from PureScript
          let found = false;
          let decodedMessage = null;

          if (matchResult !== null && matchResult !== undefined) {
            // Unwrap Maybe/Just if needed
            if (matchResult.value0 !== undefined) {
              matchResult = matchResult.value0;
            }
            found = true;
            decodedMessage = matchResult;
          }

          const requestDuration = Date.now() - requestStartTime;

          requests.push({
            hash: targetHash,
            hashIndex,
            found,
            error: null,
            duration: requestDuration,
          });

          // Check if we've exceeded the timeout
          if (Date.now() - sessionStartTime > timeoutMs) {
            requests.push({
              hash: `timeout_after_${i}_requests`,
              hashIndex: -1,
              found: false,
              error: new Error(
                `Session ${session.sessionId} timed out after ${i + 1} requests`,
              ),
              duration: Date.now() - sessionStartTime,
            });
            break;
          }
        } catch (err) {
          requests.push({
            hash: targetHash,
            hashIndex,
            found: false,
            error: err,
            duration: Date.now() - requestStartTime,
          });
        }
      }

      return {
        sessionId: session.sessionId,
        requests,
        totalDuration: Date.now() - sessionStartTime,
        completedRequests: requests.filter((r) => r.error === null).length,
        failedRequests: requests.filter((r) => r.error !== null).length,
      };
    });

    // Run all session requests in parallel with an overall timeout
    const overallTimeoutPromise = new Promise((_, reject) => {
      setTimeout(() => {
        reject(
          new Error(
            `Overall test timeout: not all sessions completed within ${timeoutSeconds} seconds`,
          ),
        );
      }, timeoutMs);
    });

    try {
      this.sessionResults = await Promise.race([
        Promise.all(sessionRequestPromises),
        overallTimeoutPromise,
      ]);
    } catch (err) {
      this.testError = err;
      return;
    }

    // Log summary
    const avgDuration =
      this.sessionResults.reduce((sum, r) => sum + r.totalDuration, 0) /
      this.sessionResults.length;
    console.log(
      `    All sessions completed. Average session duration: ${avgDuration.toFixed(0)}ms. ` +
        `Per-session: ${this.sessionResults.map((r) => `${r.sessionId}: ${r.totalDuration}ms (${r.completedRequests}/${r.requests.length})`).join(", ")}`,
    );
  },
);

Then("all sessions should complete without timeout errors", function () {
  // Skip if module not implemented
  if (this.testError) {
    if (this.testError.message.includes("not implemented yet")) {
      return "pending";
    }
    if (this.testError.message.includes("module not found")) {
      return "pending";
    }
    throw this.testError;
  }

  // Verify we have results for all sessions
  assert(
    this.sessionResults && this.sessionResults.length > 0,
    "Expected session results to be recorded",
  );

  assert.strictEqual(
    this.sessionResults.length,
    this.expectedFileCount,
    `Expected results from ${this.expectedFileCount} sessions, got ${this.sessionResults.length}`,
  );

  // Check for timeout errors in any session
  const sessionsWithTimeouts = this.sessionResults.filter((session) =>
    session.requests.some(
      (r) => r.error && r.error.message && r.error.message.includes("timeout"),
    ),
  );

  if (sessionsWithTimeouts.length > 0) {
    const timeoutDetails = sessionsWithTimeouts
      .map((s) => {
        const timeoutReq = s.requests.find(
          (r) => r.error && r.error.message.includes("timeout"),
        );
        return `Session ${s.sessionId}: ${timeoutReq.error.message}`;
      })
      .join("\n");

    assert.fail(
      `${sessionsWithTimeouts.length} sessions experienced timeout errors:\n${timeoutDetails}\n\n` +
        `This indicates the lazy loading is not properly yielding to the event loop, ` +
        `causing parallel sessions to block each other.`,
    );
  }

  // Check for any other errors
  const sessionsWithErrors = this.sessionResults.filter(
    (session) => session.failedRequests > 0,
  );

  if (sessionsWithErrors.length > 0) {
    const errorDetails = sessionsWithErrors
      .map((s) => {
        const errors = s.requests
          .filter((r) => r.error)
          .map((r) => r.error.message)
          .join(", ");
        return `Session ${s.sessionId}: ${s.failedRequests} failed - ${errors}`;
      })
      .join("\n");

    assert.fail(
      `${sessionsWithErrors.length} sessions had request errors:\n${errorDetails}`,
    );
  }

  console.log(
    `    All ${this.sessionResults.length} sessions completed without timeout errors.`,
  );
});

Then("all responses should be correct", function () {
  // Skip if module not implemented
  if (this.testError) {
    if (this.testError.message.includes("not implemented yet")) {
      return "pending";
    }
    if (this.testError.message.includes("module not found")) {
      return "pending";
    }
    throw this.testError;
  }

  // Verify all requests found their matching messages
  let totalRequests = 0;
  let foundRequests = 0;
  let missingRequests = [];

  for (const session of this.sessionResults) {
    for (const request of session.requests) {
      if (request.error) {
        continue; // Already checked in previous step
      }

      totalRequests++;

      if (request.found) {
        foundRequests++;
      } else {
        missingRequests.push({
          sessionId: session.sessionId,
          hash: request.hash,
          hashIndex: request.hashIndex,
        });
      }
    }
  }

  // All requests should have found their matches
  if (missingRequests.length > 0) {
    const missingDetails = missingRequests
      .slice(0, 10) // Show first 10 missing
      .map(
        (m) =>
          `Session ${m.sessionId}: hash "${m.hash}" (index ${m.hashIndex})`,
      )
      .join("\n");

    const moreMessage =
      missingRequests.length > 10
        ? `\n... and ${missingRequests.length - 10} more`
        : "";

    assert.fail(
      `${missingRequests.length} of ${totalRequests} requests did not find matching messages:\n` +
        `${missingDetails}${moreMessage}\n\n` +
        `This indicates the hash index was not built correctly or messages are not being found.`,
    );
  }

  // Calculate and log performance metrics
  const allDurations = this.sessionResults.flatMap((s) =>
    s.requests.filter((r) => !r.error).map((r) => r.duration),
  );

  if (allDurations.length > 0) {
    const avgDuration =
      allDurations.reduce((a, b) => a + b, 0) / allDurations.length;
    const maxDuration = Math.max(...allDurations);
    const minDuration = Math.min(...allDurations);

    console.log(
      `    All ${foundRequests}/${totalRequests} responses correct. ` +
        `Request durations - avg: ${avgDuration.toFixed(2)}ms, min: ${minDuration}ms, max: ${maxDuration}ms`,
    );
  }

  // Verify we actually tested with multiple sessions in parallel
  assert(
    this.sessionResults.length >= 2,
    `Expected at least 2 parallel sessions, got ${this.sessionResults.length}`,
  );

  // Verify we made a reasonable number of requests
  const totalSuccessfulRequests = this.sessionResults.reduce(
    (sum, s) => sum + s.completedRequests,
    0,
  );

  assert(
    totalSuccessfulRequests >= this.sessionResults.length * 5,
    `Expected at least ${this.sessionResults.length * 5} total successful requests ` +
      `(5 per session), got ${totalSuccessfulRequests}`,
  );

  console.log(
    `    Integration test passed: ${this.sessionResults.length} parallel sessions, ` +
      `${totalSuccessfulRequests} total requests, all responses correct.`,
  );
});
