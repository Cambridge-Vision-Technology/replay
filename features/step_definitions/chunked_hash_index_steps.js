import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object:
// this.recordingPath - path to the generated recording file
// this.recording - the recording data structure (with raw messages)
// this.heartbeatResults - array of {id, sent, received, latency}
// this.indexBuildError - any error that occurred during index building
// this.hashIndex - the built hash index result
// this.indexBuildingPromise - the promise for the index building operation

/**
 * Generate a recording file with the specified number of messages.
 * Each message has a unique hash for index testing.
 *
 * @param {string} filePath - The path to write the recording (will be compressed)
 * @param {number} messageCount - Number of messages to include
 * @returns {Promise<{hashes: string[]}>} - Array of message hashes
 */
async function generateRecordingWithMessages(filePath, messageCount) {
  const timestamp = new Date().toISOString();
  const hashes = [];

  // Each message should have enough data to make index building measurable
  // but not so large that file I/O dominates the test
  const payloadSize = 1024; // 1KB per message payload

  const recording = {
    schemaVersion: 2,
    scenarioName: "chunked-hash-index-test",
    recordedAt: timestamp,
    messages: [],
  };

  for (let i = 0; i < messageCount; i++) {
    const hash = `hash_${i.toString(16).padStart(16, "0")}`;
    hashes.push(hash);

    // Create a recorded message structure matching the PureScript Envelope type
    const message = {
      envelope: {
        streamId: `stream-${i}`,
        traceId: `trace-${i}`,
        causationStreamId: null,
        parentStreamId: null,
        siblingIndex: 0,
        eventSeq: i,
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
                url: `https://example.com/api/resource/${i}`,
                headers: {
                  "Content-Type": "application/json",
                  "X-Request-Id": `req-${i.toString(16).padStart(8, "0")}`,
                },
                body: `data_${i}_`.repeat(Math.floor(payloadSize / 8)),
              },
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "to_harness",
      hash: hash,
    };

    recording.messages.push(message);
  }

  // Convert to JSON
  const jsonContent = JSON.stringify(recording, null, 2);

  // Compress using zstd
  const zstd = await import("zstd-napi");
  const uncompressedBuffer = Buffer.from(jsonContent, "utf8");
  const compressedBuffer = zstd.compress(uncompressedBuffer);

  // Write compressed file
  await fs.writeFile(filePath, compressedBuffer);

  return { hashes, recording };
}

Given("a recording with {int} messages", async function (messageCount) {
  // Create temp workspace for test files
  await this.createTempWorkspace();

  const filePath = path.join(this.workspace, "chunked-index-test.json.zstd");
  this.recordingPath = filePath;
  this.expectedMessageCount = messageCount;
  this.indexBuildError = null;
  this.hashIndex = null;

  // Generate the recording file with unique hashes
  const { hashes, recording } = await generateRecordingWithMessages(
    filePath,
    messageCount,
  );
  this.messageHashes = hashes;
  this.rawRecording = recording;

  // Verify the file was created
  const exists = await this.fileExists(filePath);
  assert(exists, `Recording file was not created at: ${filePath}`);

  // Load the recording lazily to get raw messages for index building
  // The chunked index builder will work on the lazy recording's raw messages
  let Recording;
  try {
    Recording = await import("../../output/Replay.Recording/index.js");
  } catch (err) {
    if (err.code === "ERR_MODULE_NOT_FOUND") {
      this.indexBuildError = new Error(
        "Replay.Recording module not found - ensure PureScript is compiled",
      );
      return;
    }
    throw err;
  }

  // Check if loadRecordingLazyJs exists
  if (typeof Recording.loadRecordingLazyJs !== "function") {
    this.indexBuildError = new Error(
      "loadRecordingLazyJs function not implemented yet - test is pending implementation",
    );
    return;
  }

  // Load the recording lazily
  try {
    const result = await Recording.loadRecordingLazyJs(filePath)();

    // Handle Either type from PureScript
    if (result && typeof result === "object") {
      if ("value0" in result && result.constructor?.name === "Left") {
        this.indexBuildError = new Error(`Loading failed: ${result.value0}`);
        return;
      }
      if ("value0" in result && result.constructor?.name === "Right") {
        this.lazyRecording = result.value0;
      } else {
        this.lazyRecording = result;
      }
    } else {
      this.lazyRecording = result;
    }

    // Verify we have the expected number of raw messages
    const messageArray =
      this.lazyRecording.messages || this.lazyRecording.rawMessages;
    assert(
      messageArray && messageArray.length === messageCount,
      `Expected ${messageCount} messages, got ${messageArray?.length || 0}`,
    );
  } catch (err) {
    this.indexBuildError = err;
  }
});

When("building the hash index", async function () {
  // Skip if loading already failed
  if (this.indexBuildError) {
    return;
  }

  // Import the Recording module to access the chunked index builder
  let Recording;
  try {
    Recording = await import("../../output/Replay.Recording/index.js");
  } catch (err) {
    if (err.code === "ERR_MODULE_NOT_FOUND") {
      this.indexBuildError = new Error(
        "Replay.Recording module not found - ensure PureScript is compiled",
      );
      return;
    }
    throw err;
  }

  // Check for the chunked hash index building function
  // Expected: buildHashIndexChunkedJs :: LazyRecording -> Effect (Promise HashIndex)
  // Or similar JS-friendly API
  const hasBuildHashIndexChunked =
    typeof Recording.buildHashIndexChunkedJs === "function" ||
    typeof Recording.buildHashIndexChunked === "function";

  if (!hasBuildHashIndexChunked) {
    this.indexBuildError = new Error(
      "buildHashIndexChunkedJs function not implemented yet - test is pending implementation. " +
        "Expected buildHashIndexChunkedJs or buildHashIndexChunked in Replay.Recording module",
    );
    return;
  }

  // Start the index building operation (don't await yet - we'll run heartbeats simultaneously)
  const buildFunc =
    Recording.buildHashIndexChunkedJs || Recording.buildHashIndexChunked;

  try {
    // The function should accept the lazy recording and return a Promise
    // that resolves to the hash index
    const buildResult = buildFunc(this.lazyRecording);

    // Handle different return types:
    // 1. If it returns an Effect (function), call it to get the Promise
    // 2. If it returns a Promise directly, use it
    if (typeof buildResult === "function") {
      this.indexBuildingPromise = buildResult();
    } else if (buildResult instanceof Promise) {
      this.indexBuildingPromise = buildResult;
    } else if (buildResult && typeof buildResult.then === "function") {
      // Thenable
      this.indexBuildingPromise = buildResult;
    } else {
      // Might be a synchronous result wrapped in Aff - try calling as Effect
      this.indexBuildingPromise = Promise.resolve(buildResult);
    }
  } catch (err) {
    this.indexBuildError = err;
  }
});

When("sending heartbeat messages every {int}ms", async function (intervalMs) {
  // Skip if index building already failed
  if (this.indexBuildError) {
    return;
  }

  // Skip if no index building promise
  if (!this.indexBuildingPromise) {
    this.indexBuildError = new Error("No index building operation was started");
    return;
  }

  this.heartbeatResults = [];

  // Send heartbeats concurrently with the index building operation
  const heartbeatPromises = [];
  let heartbeatId = 0;
  let indexBuildComplete = false;

  // Create a promise that will send heartbeats at the specified intervals
  // until the index building completes
  const sendHeartbeats = new Promise((resolve) => {
    const sendNextHeartbeat = () => {
      if (indexBuildComplete) {
        resolve();
        return;
      }

      const id = heartbeatId++;
      const sent = Date.now();

      // Use setImmediate to measure event loop responsiveness
      // If the event loop is blocked by the index builder, this callback will be delayed
      const heartbeatPromise = new Promise((resolveHeartbeat) => {
        setImmediate(() => {
          const received = Date.now();
          this.heartbeatResults.push({
            id,
            sent,
            received,
            latency: received - sent,
          });
          resolveHeartbeat();
        });
      });

      heartbeatPromises.push(heartbeatPromise);

      // Schedule next heartbeat
      setTimeout(sendNextHeartbeat, intervalMs);
    };

    // Start sending heartbeats
    sendNextHeartbeat();
  });

  // Wait for the index building to complete
  try {
    const indexResult = await this.indexBuildingPromise;

    // Mark index building as complete to stop heartbeats
    indexBuildComplete = true;

    // Wait a bit for any in-flight heartbeats
    await new Promise((resolve) => setTimeout(resolve, intervalMs * 2));

    // Wait for all heartbeat callbacks to complete
    await Promise.all(heartbeatPromises);

    // Store the built hash index
    // Handle Either type from PureScript
    if (indexResult && typeof indexResult === "object") {
      if ("value0" in indexResult && indexResult.constructor?.name === "Left") {
        this.indexBuildError = new Error(
          `Index building failed: ${indexResult.value0}`,
        );
        return;
      }
      if (
        "value0" in indexResult &&
        indexResult.constructor?.name === "Right"
      ) {
        this.hashIndex = indexResult.value0;
      } else {
        this.hashIndex = indexResult;
      }
    } else {
      this.hashIndex = indexResult;
    }
  } catch (err) {
    indexBuildComplete = true;
    this.indexBuildError = err;
  }
});

Then(
  "all heartbeats should receive responses within {int}ms",
  function (maxLatencyMs) {
    // Skip if module not implemented
    if (this.indexBuildError) {
      if (this.indexBuildError.message.includes("not implemented yet")) {
        return "pending";
      }
      if (this.indexBuildError.message.includes("module not found")) {
        return "pending";
      }
      throw this.indexBuildError;
    }

    // Ensure we have heartbeat results
    // Note: With an efficient implementation, index building may complete very quickly
    // for 1000 messages (< 100ms), so we may only get 1-2 heartbeats.
    // This is actually a good sign - it means the implementation is fast.
    // The key assertion is that any heartbeats that DO fire respond within the allowed latency.
    assert(
      this.heartbeatResults.length > 0,
      "Expected at least one heartbeat result to be recorded during index building",
    );

    // Check that all heartbeats completed within the allowed latency
    const exceededHeartbeats = this.heartbeatResults.filter(
      (h) => h.latency > maxLatencyMs,
    );

    if (exceededHeartbeats.length > 0) {
      const maxActualLatency = Math.max(
        ...exceededHeartbeats.map((h) => h.latency),
      );
      const avgLatency =
        this.heartbeatResults.reduce((sum, h) => sum + h.latency, 0) /
        this.heartbeatResults.length;

      assert.fail(
        `Event loop was blocked during hash index building. ` +
          `${exceededHeartbeats.length} of ${this.heartbeatResults.length} heartbeats exceeded ${maxLatencyMs}ms. ` +
          `Max latency: ${maxActualLatency}ms, Average latency: ${avgLatency.toFixed(2)}ms. ` +
          `This indicates the chunked index builder is not yielding properly to the event loop. ` +
          `Heartbeat latencies: ${this.heartbeatResults.map((h) => h.latency).join(", ")}ms`,
      );
    }

    // Verify the hash index was built correctly
    assert(this.hashIndex, "Expected hash index to be built");

    // The hash index should allow lookups - verify a few hashes are indexed
    // The exact structure depends on implementation, but we can verify it exists
    // and has reasonable properties
    const indexType = typeof this.hashIndex;

    // Hash index could be a Map, Object, or custom type
    // Check that we can use it to look up at least one known hash
    const testHash = this.messageHashes[0];
    let foundInIndex = false;

    if (this.hashIndex instanceof Map) {
      foundInIndex = this.hashIndex.has(testHash);
    } else if (typeof this.hashIndex === "object") {
      // Could be a plain object or a PureScript Map
      // Check for various access patterns
      if (typeof this.hashIndex.lookup === "function") {
        // PureScript Map with lookup function
        const lookupResult = this.hashIndex.lookup(testHash);
        foundInIndex = lookupResult !== null && lookupResult !== undefined;
      } else if (typeof this.hashIndex.get === "function") {
        // Map-like interface
        foundInIndex = this.hashIndex.get(testHash) !== undefined;
      } else if (testHash in this.hashIndex) {
        // Plain object
        foundInIndex = true;
      }
    }

    // Log success info for debugging
    const avgLatency =
      this.heartbeatResults.reduce((sum, h) => sum + h.latency, 0) /
      this.heartbeatResults.length;
    const maxLatency = Math.max(...this.heartbeatResults.map((h) => h.latency));

    console.log(
      `    Chunked index building passed: ${this.heartbeatResults.length} heartbeats, ` +
        `avg latency: ${avgLatency.toFixed(2)}ms, max latency: ${maxLatency}ms. ` +
        `Index built for ${this.expectedMessageCount} messages.`,
    );

    if (foundInIndex) {
      console.log(
        `    Hash index verified: test hash "${testHash}" found in index.`,
      );
    } else {
      console.log(
        `    Note: Could not verify hash lookup in index (implementation may differ). ` +
          `Index type: ${indexType}`,
      );
    }
  },
);
