import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object:
// this.largeRecordingPath - path to the generated compressed recording file
// this.lazyRecording - the lazily loaded recording result
// this.heartbeatResults - array of {id, sent, received, latency}
// this.loadError - any error that occurred during loading
// this.loadingPromise - the promise for the loading operation

/**
 * Generate a large compressed recording file for testing.
 * Creates a recording with the specified number of messages, where each message
 * has enough payload data to reach approximately the target total size.
 *
 * @param {string} filePath - The path to write the recording (will be compressed)
 * @param {number} messageCount - Number of messages to include
 * @param {number} targetSizeMB - Target total size in megabytes
 * @returns {Promise<{uncompressedSize: number, compressedSize: number}>}
 */
async function generateLargeRecording(filePath, messageCount, targetSizeMB) {
  const targetSizeBytes = targetSizeMB * 1024 * 1024;
  const bytesPerMessage = Math.floor(targetSizeBytes / messageCount);

  // Base message structure overhead (approximate JSON size without payload)
  const baseMessageSize = 500;
  const paddingSize = Math.max(0, bytesPerMessage - baseMessageSize);

  const timestamp = new Date().toISOString();

  const recording = {
    schemaVersion: 2,
    scenarioName: "lazy-loading-performance-test",
    recordedAt: timestamp,
    messages: [],
  };

  for (let i = 0; i < messageCount; i++) {
    // Create a realistic recorded message structure matching Recording.purs
    const message = {
      envelope: {
        version: "1.0.0",
        timestamp: timestamp,
        sessionId: `session-${i}`,
        payload: {
          kind: "command",
          data: {
            tag: "CommandOpen",
            contents: {
              service: "http",
              method: "GET",
              url: `https://example.com/api/resource/${i}`,
              headers: {
                "Content-Type": "application/json",
                "X-Request-Id": `req-${i.toString(16).padStart(8, "0")}`,
              },
              // Add padding to reach target size
              body: "x".repeat(paddingSize),
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "Outgoing",
      hash: `hash_${i.toString(16).padStart(16, "0")}`,
    };

    recording.messages.push(message);
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

  return { uncompressedSize, compressedSize };
}

Given(
  "a compressed recording file with {int} messages totaling {int}MB",
  async function (messageCount, targetSizeMB) {
    // Create temp workspace for test files
    await this.createTempWorkspace();

    const filePath = path.join(this.workspace, "large-recording.json.zstd");
    this.largeRecordingPath = filePath;
    this.expectedMessageCount = messageCount;
    this.expectedSizeMB = targetSizeMB;

    // Generate the large recording file
    const { uncompressedSize, compressedSize } = await generateLargeRecording(
      filePath,
      messageCount,
      targetSizeMB,
    );

    // Store sizes for verification
    this.uncompressedSizeMB = uncompressedSize / (1024 * 1024);
    this.compressedSizeMB = compressedSize / (1024 * 1024);

    // Verify the uncompressed size is approximately correct
    // Allow 20% variance due to JSON encoding overhead and compression behavior
    const minExpectedMB = targetSizeMB * 0.8;
    const maxExpectedMB = targetSizeMB * 1.2;

    assert(
      this.uncompressedSizeMB >= minExpectedMB &&
        this.uncompressedSizeMB <= maxExpectedMB,
      `Expected uncompressed size to be approximately ${targetSizeMB}MB, ` +
        `got ${this.uncompressedSizeMB.toFixed(2)}MB`,
    );

    // Verify the file was created
    const exists = await this.fileExists(filePath);
    assert(exists, `Recording file was not created at: ${filePath}`);
  },
);

When("I start loading the recording", async function () {
  this.heartbeatResults = [];
  this.loadError = null;
  this.lazyRecording = null;

  // Import the lazy recording loader
  // This will be implemented at src/Replay/Recording.purs as loadRecordingLazy
  let Recording;
  try {
    Recording = await import("../../output/Replay.Recording/index.js");
  } catch (err) {
    if (err.code === "ERR_MODULE_NOT_FOUND") {
      this.loadError = new Error(
        "Replay.Recording module not found - ensure PureScript is compiled",
      );
      return;
    }
    throw err;
  }

  // Check if loadRecordingLazyJs exists (JS-friendly version that returns Effect (Promise ...))
  if (typeof Recording.loadRecordingLazyJs !== "function") {
    this.loadError = new Error(
      "loadRecordingLazyJs function not implemented yet - test is pending implementation",
    );
    return;
  }

  // Start the loading operation (don't await yet - we'll run heartbeats simultaneously)
  // The loadRecordingLazyJs function returns an Effect that produces a Promise
  try {
    this.loadingPromise = Recording.loadRecordingLazyJs(
      this.largeRecordingPath,
    )();
  } catch (err) {
    this.loadError = err;
  }
});

When(
  "simultaneously send {int} heartbeat messages at {int}ms intervals",
  async function (heartbeatCount, intervalMs) {
    // Skip if loading already failed
    if (this.loadError) {
      return;
    }

    // Skip if no loading promise
    if (!this.loadingPromise) {
      this.loadError = new Error("No loading operation was started");
      return;
    }

    // Send heartbeats concurrently with the loading operation
    const heartbeatPromises = [];
    let heartbeatId = 0;

    // Create a promise that will send all heartbeats at the specified intervals
    const sendHeartbeats = new Promise((resolve) => {
      const sendNextHeartbeat = () => {
        if (heartbeatId >= heartbeatCount) {
          resolve();
          return;
        }

        const id = heartbeatId++;
        const sent = Date.now();

        // Use setImmediate to measure event loop responsiveness
        // If the event loop is blocked by the loader, this callback will be delayed
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

    // Wait for both the loading to complete and all heartbeats to be sent
    try {
      const [loadResult] = await Promise.all([
        this.loadingPromise,
        sendHeartbeats,
      ]);

      // Wait for all heartbeat callbacks to complete
      await Promise.all(heartbeatPromises);

      // Store the loaded recording
      this.lazyRecording = loadResult;
    } catch (err) {
      this.loadError = err;
    }
  },
);

Then(
  "all heartbeat responses should arrive within {int}ms of sending",
  function (maxLatencyMs) {
    // Skip if module not implemented
    if (this.loadError) {
      if (this.loadError.message.includes("not implemented yet")) {
        return "pending";
      }
      if (this.loadError.message.includes("module not found")) {
        return "pending";
      }
      throw this.loadError;
    }

    // Ensure we have heartbeat results
    assert(
      this.heartbeatResults.length > 0,
      "Expected heartbeat results to be recorded during loading",
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
        `Event loop was blocked during recording loading. ` +
          `${exceededHeartbeats.length} of ${this.heartbeatResults.length} heartbeats exceeded ${maxLatencyMs}ms. ` +
          `Max latency: ${maxActualLatency}ms, Average latency: ${avgLatency.toFixed(2)}ms. ` +
          `This indicates the lazy loader is blocking the event loop. ` +
          `Heartbeat latencies: ${this.heartbeatResults.map((h) => h.latency).join(", ")}ms`,
      );
    }

    // Log success info for debugging
    const avgLatency =
      this.heartbeatResults.reduce((sum, h) => sum + h.latency, 0) /
      this.heartbeatResults.length;
    const maxLatency = Math.max(...this.heartbeatResults.map((h) => h.latency));

    console.log(
      `    Heartbeat check passed: ${this.heartbeatResults.length} heartbeats, ` +
        `avg latency: ${avgLatency.toFixed(2)}ms, max latency: ${maxLatency}ms`,
    );
  },
);

Then("the recording metadata should be available", function () {
  // Skip if module not implemented
  if (this.loadError) {
    if (this.loadError.message.includes("not implemented yet")) {
      return "pending";
    }
    if (this.loadError.message.includes("module not found")) {
      return "pending";
    }
    throw this.loadError;
  }

  // Verify the lazy recording was loaded
  assert(this.lazyRecording, "Expected lazy recording to be loaded");

  // Check that metadata is available without needing to decode all messages
  // The LazyRecording type should expose metadata fields

  // Handle Either type from PureScript - check for Left/Right
  let recording = this.lazyRecording;

  // If it's an Either, unwrap it
  if (recording && typeof recording === "object") {
    if ("value0" in recording && recording.constructor?.name === "Left") {
      assert.fail(`Loading failed with error: ${recording.value0}`);
    }
    if ("value0" in recording && recording.constructor?.name === "Right") {
      recording = recording.value0;
    }
  }

  // Verify schema version is present and valid
  assert(
    typeof recording.schemaVersion === "number",
    `Expected schemaVersion to be a number, got ${typeof recording.schemaVersion}`,
  );
  assert(
    recording.schemaVersion >= 1 && recording.schemaVersion <= 2,
    `Expected valid schemaVersion (1 or 2), got ${recording.schemaVersion}`,
  );

  // Verify scenario name is present
  assert(
    typeof recording.scenarioName === "string" &&
      recording.scenarioName.length > 0,
    `Expected scenarioName to be a non-empty string, got: ${recording.scenarioName}`,
  );

  // Verify recordedAt timestamp is present
  assert(
    typeof recording.recordedAt === "string" && recording.recordedAt.length > 0,
    `Expected recordedAt to be a non-empty string, got: ${recording.recordedAt}`,
  );

  // Verify the message count matches expectations (if the lazy recording exposes this)
  // For a lazy recording, messages might be stored as raw JSON or have a count property
  if (recording.messageCount !== undefined) {
    assert.strictEqual(
      recording.messageCount,
      this.expectedMessageCount,
      `Expected ${this.expectedMessageCount} messages, got ${recording.messageCount}`,
    );
  } else if (recording.messages !== undefined) {
    // If messages array is exposed (even as lazy/raw entries)
    assert.strictEqual(
      recording.messages.length,
      this.expectedMessageCount,
      `Expected ${this.expectedMessageCount} messages, got ${recording.messages.length}`,
    );
  } else if (recording.rawMessages !== undefined) {
    // Alternative: messages stored as raw JSON strings
    assert.strictEqual(
      recording.rawMessages.length,
      this.expectedMessageCount,
      `Expected ${this.expectedMessageCount} raw messages, got ${recording.rawMessages.length}`,
    );
  }

  // Log success info
  console.log(
    `    Recording metadata loaded: schemaVersion=${recording.schemaVersion}, ` +
      `scenarioName="${recording.scenarioName}", ` +
      `recordedAt="${recording.recordedAt}"`,
  );
});
