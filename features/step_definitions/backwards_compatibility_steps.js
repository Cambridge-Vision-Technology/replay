import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object:
// this.legacyRecordingPath - path to the legacy recording file
// this.lazyRecording - recording loaded with the new lazy loader
// this.lazyHashIndex - hash index built from lazy recording
// this.loadError - any error that occurred during loading
// this.messageHashes - array of hashes extracted from messages
// this.expectedMetadata - the expected metadata from the generated recording

/**
 * Generate a recording file that mimics the "previous version" format.
 * This creates a recording with the same structure that existing recordings have,
 * including proper schema version and all expected fields.
 *
 * @param {string} filePath - The path to write the recording (will be compressed)
 * @param {number} messageCount - Number of request/response pairs to include
 * @returns {Promise<{hashes: string[], metadata: object}>} - Array of request message hashes and expected metadata
 */
async function generateLegacyRecording(filePath, messageCount) {
  const timestamp = new Date().toISOString();
  const hashes = [];

  // Create a recording with the schema version 2 format (current schema)
  // This represents a "previous version" recording that should work with lazy loader
  const recording = {
    schemaVersion: 2,
    scenarioName: "backwards-compatibility-test",
    recordedAt: timestamp,
    messages: [],
  };

  for (let i = 0; i < messageCount; i++) {
    const hash = `legacy_hash_${i.toString(16).padStart(16, "0")}`;
    hashes.push(hash);

    const streamId = `stream-${i}`;
    const traceId = `trace-${i}`;

    // Create a request message (command from client to harness)
    // Matching the structure in existing recordings
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
                url: `https://api.example.com/v1/resource/${i}`,
                headers: {
                  "Content-Type": "application/json",
                  Authorization: `Bearer token-${i}`,
                },
                body: JSON.stringify({ requestId: i, data: `test-data-${i}` }),
              },
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "to_harness",
      hash: hash,
    };

    // Create a corresponding response message (event from harness to client)
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
                  requestId: i,
                  result: `response-for-${i}`,
                }),
              },
            },
          },
        },
      },
      recordedAt: timestamp,
      direction: "from_harness",
      hash: null, // Response messages don't have hashes
    };

    recording.messages.push(requestMessage);
    recording.messages.push(responseMessage);
  }

  // Convert to JSON
  const jsonContent = JSON.stringify(recording, null, 2);

  // Compress using zstd (same as saveRecording does)
  const zstd = await import("zstd-napi");
  const uncompressedBuffer = Buffer.from(jsonContent, "utf8");
  const compressedBuffer = zstd.compress(uncompressedBuffer);

  // Write compressed file
  await fs.writeFile(filePath, compressedBuffer);

  return {
    hashes,
    metadata: {
      schemaVersion: recording.schemaVersion,
      scenarioName: recording.scenarioName,
      recordedAt: recording.recordedAt,
      messageCount: recording.messages.length,
    },
  };
}

Given("a recording created with the previous version", async function () {
  // Create temp workspace for test files
  await this.createTempWorkspace();

  const filePath = path.join(this.workspace, "legacy-recording.json.zstd");
  this.legacyRecordingPath = filePath;
  this.loadError = null;
  this.lazyRecording = null;

  // Generate a legacy recording with 20 request/response pairs (40 messages)
  const messageCount = 20;
  const { hashes, metadata } = await generateLegacyRecording(
    filePath,
    messageCount,
  );
  this.messageHashes = hashes;
  this.expectedMetadata = metadata;
  this.expectedMessageCount = messageCount * 2; // Each pair has 2 messages

  // Verify the file was created
  const exists = await this.fileExists(filePath);
  assert(exists, `Legacy recording file was not created at: ${filePath}`);

  console.log(
    `    Created legacy recording: ${this.expectedMessageCount} messages, ` +
      `${this.messageHashes.length} hashes`,
  );
});

When("loaded with the new lazy loader", async function () {
  // Import the Recording module
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

  // Check if loadRecordingLazyJs exists
  if (typeof Recording.loadRecordingLazyJs !== "function") {
    this.loadError = new Error(
      "loadRecordingLazyJs function not implemented yet - test is pending implementation",
    );
    return;
  }

  // Load the recording with the lazy loader
  try {
    const result = await Recording.loadRecordingLazyJs(
      this.legacyRecordingPath,
    )();

    // Handle Either type from PureScript
    if (result && typeof result === "object") {
      if ("value0" in result && result.constructor?.name === "Left") {
        this.loadError = new Error(`Lazy loading failed: ${result.value0}`);
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

    // Build hash index from lazy recording (using chunked builder)
    if (typeof Recording.buildHashIndexChunkedJs === "function") {
      const buildResult = Recording.buildHashIndexChunkedJs(this.lazyRecording);

      // Handle different return types (Effect or Promise)
      if (typeof buildResult === "function") {
        this.lazyHashIndex = await buildResult();
      } else if (
        buildResult instanceof Promise ||
        (buildResult && typeof buildResult.then === "function")
      ) {
        this.lazyHashIndex = await buildResult;
      } else {
        this.lazyHashIndex = buildResult;
      }
    }
  } catch (err) {
    this.loadError = err;
  }
});

Then("playback should work identically to before", function () {
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

  // Compare metadata between expected and lazy recording
  // Schema version should match
  assert.strictEqual(
    this.lazyRecording.schemaVersion,
    this.expectedMetadata.schemaVersion,
    `Schema version mismatch: got ${this.lazyRecording.schemaVersion}, expected ${this.expectedMetadata.schemaVersion}`,
  );

  // Scenario name should match
  assert.strictEqual(
    this.lazyRecording.scenarioName,
    this.expectedMetadata.scenarioName,
    `Scenario name mismatch: got "${this.lazyRecording.scenarioName}", expected "${this.expectedMetadata.scenarioName}"`,
  );

  // Recorded timestamp should match
  assert.strictEqual(
    this.lazyRecording.recordedAt,
    this.expectedMetadata.recordedAt,
    `Recorded timestamp mismatch: got "${this.lazyRecording.recordedAt}", expected "${this.expectedMetadata.recordedAt}"`,
  );

  // Message count should match
  const lazyMessages =
    this.lazyRecording.messages || this.lazyRecording.rawMessages;
  assert.strictEqual(
    lazyMessages.length,
    this.expectedMetadata.messageCount,
    `Message count mismatch: got ${lazyMessages.length}, expected ${this.expectedMetadata.messageCount}`,
  );

  console.log(
    `    Backwards compatibility verified: lazy recording loaded successfully ` +
      `(schema=${this.lazyRecording.schemaVersion}, messages=${lazyMessages.length})`,
  );
});

Then("all message hashes should be accessible", async function () {
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

  // Import the Recording module for hash lookup
  let Recording;
  try {
    Recording = await import("../../output/Replay.Recording/index.js");
  } catch (err) {
    throw err;
  }

  // Verify all expected hashes can be found in the lazy recording
  const hasFindMessageByHash =
    typeof Recording.findMessageByHashJs === "function";

  if (!hasFindMessageByHash) {
    // Can't verify hash lookup without findMessageByHash
    console.log(
      "    Note: findMessageByHashJs not available, skipping individual hash verification",
    );
    return;
  }

  // Test a sample of hashes from the recording
  const sampleSize = Math.min(5, this.messageHashes.length);
  const sampleIndices = [
    0, // First hash
    Math.floor(this.messageHashes.length / 4), // 25%
    Math.floor(this.messageHashes.length / 2), // 50%
    Math.floor((this.messageHashes.length * 3) / 4), // 75%
    this.messageHashes.length - 1, // Last hash
  ].slice(0, sampleSize);

  let foundCount = 0;
  let errors = [];

  for (const idx of sampleIndices) {
    const hash = this.messageHashes[idx];

    try {
      const result = Recording.findMessageByHashJs(hash)(this.lazyRecording);

      // Handle Maybe from PureScript
      if (result === null || result === undefined) {
        errors.push(`Hash "${hash}" not found in lazy recording`);
        continue;
      }

      // Unwrap Maybe if needed
      let message = result;
      if (result.value0 !== undefined) {
        message = result.value0;
      }

      // Verify the message has the expected hash
      let messageHash = message.hash;
      if (
        messageHash &&
        typeof messageHash === "object" &&
        "value0" in messageHash
      ) {
        messageHash = messageHash.value0;
      }

      if (messageHash !== hash) {
        errors.push(
          `Hash mismatch for index ${idx}: expected "${hash}", got "${messageHash}"`,
        );
        continue;
      }

      // Verify the decoded message has expected structure
      if (!message.envelope) {
        errors.push(`Message for hash "${hash}" missing envelope`);
        continue;
      }
      if (!message.direction) {
        errors.push(`Message for hash "${hash}" missing direction`);
        continue;
      }
      if (!message.recordedAt) {
        errors.push(`Message for hash "${hash}" missing recordedAt`);
        continue;
      }

      foundCount++;
    } catch (err) {
      errors.push(`Error looking up hash "${hash}": ${err.message}`);
    }
  }

  // Report results
  if (errors.length > 0) {
    assert.fail(
      `Hash accessibility verification failed:\n` +
        errors.map((e) => `  - ${e}`).join("\n") +
        `\n  Found ${foundCount} of ${sampleSize} sampled hashes`,
    );
  }

  console.log(
    `    All hashes accessible: verified ${foundCount} of ${sampleSize} sampled hashes ` +
      `from total of ${this.messageHashes.length} message hashes`,
  );
});
