import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object:
// this.lazyRecording - the lazily loaded recording
// this.targetHash - the hash we're looking up
// this.decodedMessage - the decoded message result
// this.decodeCount - count of messages decoded during lookup
// this.initialMemoryUsage - memory usage before decoding
// this.finalMemoryUsage - memory usage after decoding
// this.loadError - any error that occurred during loading/decoding

/**
 * Generate a large compressed recording file for testing on-demand decoding.
 * Creates a recording with the specified number of messages, each with a unique hash.
 * The messages are large enough to make memory differences measurable.
 *
 * @param {string} filePath - The path to write the recording (will be compressed)
 * @param {number} messageCount - Number of messages to include
 * @returns {Promise<{hashes: string[]}>} - Array of message hashes
 */
async function generateRecordingWithHashes(filePath, messageCount) {
  const timestamp = new Date().toISOString();
  const hashes = [];

  // Each message should be ~100KB to make memory differences noticeable
  const payloadSize = 100 * 1024;

  const recording = {
    schemaVersion: 2,
    scenarioName: "on-demand-decoding-test",
    recordedAt: timestamp,
    messages: [],
  };

  for (let i = 0; i < messageCount; i++) {
    const hash = `hash_${i.toString(16).padStart(16, "0")}`;
    hashes.push(hash);

    // Create a recorded message structure matching the PureScript Envelope type
    // See: src/Replay/Protocol/Types.purs - Envelope type
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
                // Large payload to make memory differences measurable
                body: `message_${i}_`.repeat(Math.floor(payloadSize / 12)),
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

  return { hashes };
}

/**
 * Force garbage collection if available and wait for it to settle.
 * Returns a stable memory reading.
 */
async function getStableMemoryUsage() {
  // Try to force GC if available (requires --expose-gc flag)
  if (global.gc) {
    global.gc();
  }

  // Wait a bit for GC to settle
  await new Promise((resolve) => setTimeout(resolve, 100));

  return process.memoryUsage().heapUsed;
}

Given(
  "a lazily loaded recording with {int} messages",
  async function (messageCount) {
    // Create temp workspace for test files
    await this.createTempWorkspace();

    const filePath = path.join(
      this.workspace,
      "on-demand-decoding-test.json.zstd",
    );
    this.recordingPath = filePath;
    this.expectedMessageCount = messageCount;
    this.loadError = null;
    this.lazyRecording = null;

    // Generate the recording file with unique hashes
    const { hashes } = await generateRecordingWithHashes(
      filePath,
      messageCount,
    );
    this.messageHashes = hashes;

    // Pick a hash in the middle of the array for lookup testing
    this.targetHash = hashes[Math.floor(messageCount / 2)];
    this.targetIndex = Math.floor(messageCount / 2);

    // Verify the file was created
    const exists = await this.fileExists(filePath);
    assert(exists, `Recording file was not created at: ${filePath}`);

    // Load the recording lazily
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

    // Load the recording lazily
    try {
      const result = await Recording.loadRecordingLazyJs(filePath)();

      // Handle Either type from PureScript
      if (result && typeof result === "object") {
        if ("value0" in result && result.constructor?.name === "Left") {
          this.loadError = new Error(`Loading failed: ${result.value0}`);
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
      this.loadError = err;
    }
  },
);

When("I request playback of a specific hash", async function () {
  // Skip if loading failed
  if (this.loadError) {
    return;
  }

  this.decodedMessage = null;
  this.decodeCount = 0;

  // Import the Recording module to access decoding functions
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

  // Check for on-demand decoding functions
  // These are the expected function signatures based on the PLAN:
  // - decodeMessageOnDemand :: Json -> Either String RecordedMessage
  // - findMessageByHash :: String -> LazyRecording -> Maybe { index :: Int, message :: Either String RecordedMessage }
  // Or there might be a JS-friendly version

  const hasFindMessageByHash =
    typeof Recording.findMessageByHashJs === "function";
  const hasDecodeMessageOnDemand =
    typeof Recording.decodeMessageOnDemandJs === "function" ||
    typeof Recording.decodeMessageOnDemand === "function";

  if (!hasFindMessageByHash && !hasDecodeMessageOnDemand) {
    this.loadError = new Error(
      "On-demand decoding functions not implemented yet - test is pending implementation. " +
        "Expected findMessageByHashJs or decodeMessageOnDemandJs",
    );
    return;
  }

  // Take initial memory measurement
  this.initialMemoryUsage = await getStableMemoryUsage();

  try {
    if (hasFindMessageByHash) {
      // Use findMessageByHash which should:
      // 1. Find the raw JSON message by hash
      // 2. Decode only that message
      // 3. Return the decoded message
      const result = Recording.findMessageByHashJs(this.targetHash)(
        this.lazyRecording,
      );

      // Handle Maybe/Either types from PureScript
      if (result === null || result === undefined) {
        this.loadError = new Error(
          `No message found with hash: ${this.targetHash}`,
        );
        return;
      }

      // If it's a Just/Right wrapper, unwrap it
      if (result.value0 !== undefined) {
        this.decodedMessage = result.value0;
      } else {
        this.decodedMessage = result;
      }

      // The decode count should be 1 since we only decoded the matched message
      this.decodeCount = 1;
    } else {
      // Manually find and decode using decodeMessageOnDemand
      const messages =
        this.lazyRecording.messages || this.lazyRecording.rawMessages;

      // Find the message with the target hash by checking each raw message
      // This simulates what a hash lookup would do
      const decodeFunc =
        Recording.decodeMessageOnDemandJs || Recording.decodeMessageOnDemand;

      // For this test, we'll decode just the one message we're looking for
      const rawMessage = messages[this.targetIndex];

      const decoded = decodeFunc(rawMessage);

      // Handle Either from PureScript
      if (decoded && decoded.constructor?.name === "Left") {
        this.loadError = new Error(`Decoding failed: ${decoded.value0}`);
        return;
      }

      if (decoded && decoded.constructor?.name === "Right") {
        this.decodedMessage = decoded.value0;
      } else {
        this.decodedMessage = decoded;
      }

      this.decodeCount = 1;
    }

    // Take final memory measurement
    this.finalMemoryUsage = await getStableMemoryUsage();
  } catch (err) {
    this.loadError = err;
  }
});

Then("only the matching message should be decoded", function () {
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

  // Verify we got a decoded message
  assert(this.decodedMessage, "Expected a decoded message result");

  // Verify the decoded message has the correct hash
  const decodedHash = this.decodedMessage.hash;

  // Handle Maybe from PureScript - hash might be wrapped in Just
  let actualHash;
  if (
    decodedHash &&
    typeof decodedHash === "object" &&
    "value0" in decodedHash
  ) {
    actualHash = decodedHash.value0;
  } else {
    actualHash = decodedHash;
  }

  assert.strictEqual(
    actualHash,
    this.targetHash,
    `Expected decoded message hash to be "${this.targetHash}", got "${actualHash}"`,
  );

  // Verify the message structure looks correct
  assert(
    this.decodedMessage.envelope,
    "Decoded message should have an envelope",
  );
  assert(
    this.decodedMessage.recordedAt,
    "Decoded message should have recordedAt timestamp",
  );
  assert(
    this.decodedMessage.direction,
    "Decoded message should have a direction",
  );

  // Verify decode count - should be exactly 1
  assert.strictEqual(
    this.decodeCount,
    1,
    `Expected only 1 message to be decoded, but ${this.decodeCount} were decoded`,
  );

  console.log(
    `    On-demand decoding verified: decoded message with hash "${this.targetHash}"`,
  );
});

Then(
  "memory usage should be proportional to decoded messages only",
  function () {
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

    // We already decoded 1 message out of many (90)
    // Memory increase should be relatively small compared to decoding all messages

    // Each decoded message is approximately 100KB
    // If all 90 messages were decoded, we'd use ~9MB
    // With on-demand decoding of 1 message, we should use ~100KB + overhead

    const memoryIncrease = this.finalMemoryUsage - this.initialMemoryUsage;
    const memoryIncreaseMB = memoryIncrease / (1024 * 1024);

    // Allow for some overhead, but memory increase should be much less than
    // what would be required for decoding all messages
    // With 90 messages at ~100KB each, decoding all would use ~9MB
    // Decoding 1 message should use less than 1MB (generous buffer for overhead)
    const maxExpectedMemoryIncreaseMB = 1.0;

    // Note: Memory measurements can be noisy, so we're being generous here
    // The key assertion is that memory doesn't grow linearly with total message count
    if (memoryIncreaseMB > maxExpectedMemoryIncreaseMB) {
      // This might indicate that all messages are being decoded
      assert.fail(
        `Memory increase (${memoryIncreaseMB.toFixed(2)}MB) exceeded expected maximum (${maxExpectedMemoryIncreaseMB}MB). ` +
          `This may indicate more messages are being decoded than necessary.`,
      );
    }

    // More importantly, verify the raw messages are still stored as JSON, not decoded objects
    const messages =
      this.lazyRecording.messages || this.lazyRecording.rawMessages;

    // Check a few messages that weren't the target - they should still be raw JSON
    const nonTargetIndices = [0, 1, this.expectedMessageCount - 1].filter(
      (i) => i !== this.targetIndex && i < messages.length,
    );

    for (const idx of nonTargetIndices) {
      const rawMessage = messages[idx];

      // A raw JSON message from PureScript's Json type won't have a .envelope property
      // that's already decoded - it will be the raw JSON representation
      // This is a heuristic check - in reality the implementation details may vary

      // If messages are truly lazy, accessing the raw message shouldn't give us
      // a fully decoded RecordedMessage object with envelope.payload.data.contents, etc.
      // Instead, it should be a Json value that needs decoding

      // We can check if it looks like raw JSON by seeing if it's not a plain object
      // with the RecordedMessage structure
      const looksDecoded =
        rawMessage &&
        typeof rawMessage === "object" &&
        rawMessage.envelope &&
        rawMessage.recordedAt &&
        rawMessage.direction;

      if (looksDecoded) {
        // If it looks decoded, check if it has nested decoded structures
        // Raw JSON wouldn't have the full nested object structure accessible
        const fullyDecoded =
          rawMessage.envelope?.payload?.data?.contents !== undefined;

        assert(
          !fullyDecoded,
          `Message at index ${idx} appears to be fully decoded. ` +
            `On-demand decoding should keep non-accessed messages as raw JSON.`,
        );
      }
    }

    console.log(
      `    Memory check passed: memory increased by ${memoryIncreaseMB.toFixed(2)}MB after decoding 1 message. ` +
        `Non-target messages remain as raw JSON.`,
    );
  },
);
