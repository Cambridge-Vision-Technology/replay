import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

// Test state stored on the world object
// this.largeJsonFilePath - path to the generated test file
// this.parsedObjects - array of objects parsed from the stream
// this.heartbeatResults - array of {sent: timestamp, received: timestamp}
// this.parseError - any error that occurred during parsing

/**
 * Generates a large JSON file with the specified number of objects.
 * Each object contains enough data to reach approximately the target size.
 */
async function generateLargeJsonFile(filePath, targetSizeMB, objectCount) {
  // Calculate approximate size per object to reach target
  const targetSizeBytes = targetSizeMB * 1024 * 1024;
  const bytesPerObject = Math.floor(targetSizeBytes / objectCount);

  // Create a template object and pad it to reach the target size per object
  // We need to account for JSON overhead (brackets, commas, etc.)
  const baseObjectSize = 200; // approximate base object JSON size
  const paddingSize = Math.max(0, bytesPerObject - baseObjectSize);

  const objects = [];
  for (let i = 0; i < objectCount; i++) {
    objects.push({
      id: i,
      timestamp: Date.now(),
      type: "test_message",
      data: {
        index: i,
        hash: `hash_${i.toString(16).padStart(8, "0")}`,
        // Add padding to reach target size
        payload: "x".repeat(paddingSize),
      },
      metadata: {
        version: "1.0.0",
        source: "streaming_json_test",
      },
    });
  }

  await fs.writeFile(filePath, JSON.stringify(objects));
  return objects.length;
}

Given(
  "a 50MB JSON file containing an array of {int} objects",
  async function (objectCount) {
    // Create temp workspace for test files
    await this.createTempWorkspace();

    const filePath = path.join(this.workspace, "large_test_data.json");
    this.largeJsonFilePath = filePath;
    this.expectedObjectCount = objectCount;

    // Generate the large JSON file
    await generateLargeJsonFile(filePath, 50, objectCount);

    // Verify the file was created and is approximately the right size
    const stats = await fs.stat(filePath);
    const sizeMB = stats.size / (1024 * 1024);

    // Allow some variance (40-60MB) due to JSON encoding overhead
    assert(
      sizeMB >= 40 && sizeMB <= 60,
      `Expected file to be approximately 50MB, got ${sizeMB.toFixed(2)}MB`,
    );
  },
);

When("I parse the file using the streaming parser", async function () {
  this.parsedObjects = [];
  this.heartbeatResults = [];
  this.parseError = null;

  // Import the streaming JSON parser FFI
  // This will be implemented at src/FFI/JsonStream.js
  let JsonStream;
  try {
    JsonStream = await import("../../output/FFI.JsonStream/index.js");
  } catch (err) {
    // If the module doesn't exist yet, we'll skip with a pending message
    if (err.code === "ERR_MODULE_NOT_FOUND") {
      this.parseError = new Error(
        "FFI.JsonStream module not implemented yet - test is pending implementation",
      );
      return;
    }
    throw err;
  }

  // Start heartbeat monitoring - send heartbeats every 50ms
  // and track when they complete to measure event loop responsiveness
  const heartbeatInterval = 50;
  let heartbeatId = 0;
  const heartbeatPromises = [];

  const heartbeatTimer = setInterval(() => {
    const sent = Date.now();
    const id = heartbeatId++;

    // Use setImmediate to measure event loop responsiveness
    // If the event loop is blocked, this callback will be delayed
    const promise = new Promise((resolve) => {
      setImmediate(() => {
        const received = Date.now();
        this.heartbeatResults.push({
          id,
          sent,
          received,
          latency: received - sent,
        });
        resolve();
      });
    });
    heartbeatPromises.push(promise);
  }, heartbeatInterval);

  try {
    // Parse the file using the streaming parser
    // The parser should emit objects one at a time without blocking
    const fileContent = await fs.readFile(this.largeJsonFilePath);

    // Call the streaming parser - it should return an async iterator or similar
    // that yields parsed objects without blocking the event loop
    const parseResult = await JsonStream.parseArrayStream(fileContent)();

    // Collect all parsed objects
    if (Symbol.asyncIterator in parseResult) {
      // If it's an async iterator, collect objects as they stream
      for await (const obj of parseResult) {
        this.parsedObjects.push(obj);
      }
    } else if (Array.isArray(parseResult)) {
      // If it returns an array directly, use that
      this.parsedObjects = parseResult;
    } else {
      throw new Error(`Unexpected parse result type: ${typeof parseResult}`);
    }
  } catch (err) {
    this.parseError = err;
  } finally {
    // Stop heartbeat monitoring
    clearInterval(heartbeatTimer);

    // Wait for any pending heartbeat callbacks
    await Promise.all(heartbeatPromises);
  }
});

Then(
  "the event loop should remain responsive \\(heartbeat messages continue)",
  function () {
    // Skip if module not implemented
    if (
      this.parseError &&
      this.parseError.message.includes("not implemented yet")
    ) {
      return "pending";
    }

    // Check that heartbeats were recorded
    assert(
      this.heartbeatResults.length > 0,
      "Expected heartbeat results to be recorded during parsing",
    );

    // Check that no heartbeat took longer than 100ms (allowing some overhead)
    // A truly non-blocking parser should allow heartbeats to complete quickly
    const maxAcceptableLatency = 100;
    const blockedHeartbeats = this.heartbeatResults.filter(
      (h) => h.latency > maxAcceptableLatency,
    );

    if (blockedHeartbeats.length > 0) {
      const maxLatency = Math.max(...blockedHeartbeats.map((h) => h.latency));
      assert.fail(
        `Event loop was blocked - ${blockedHeartbeats.length} heartbeats exceeded ${maxAcceptableLatency}ms. ` +
          `Max latency: ${maxLatency}ms. ` +
          `This indicates the JSON parser is blocking the event loop.`,
      );
    }

    // Also verify heartbeats continued throughout parsing (not just at start/end)
    const minExpectedHeartbeats = 5; // With 50ms intervals, we expect many during 50MB parse
    assert(
      this.heartbeatResults.length >= minExpectedHeartbeats,
      `Expected at least ${minExpectedHeartbeats} heartbeats during parsing, got ${this.heartbeatResults.length}. ` +
        `This may indicate parsing completed too quickly or heartbeat monitoring failed.`,
    );
  },
);

Then("all objects should be parsed correctly", function () {
  // Skip if module not implemented
  if (
    this.parseError &&
    this.parseError.message.includes("not implemented yet")
  ) {
    return "pending";
  }

  // Re-throw any other parse errors
  if (this.parseError) {
    throw this.parseError;
  }

  // Verify we got the expected number of objects
  assert.strictEqual(
    this.parsedObjects.length,
    this.expectedObjectCount,
    `Expected ${this.expectedObjectCount} objects, got ${this.parsedObjects.length}`,
  );

  // Verify each object has the expected structure
  for (let i = 0; i < this.parsedObjects.length; i++) {
    const obj = this.parsedObjects[i];

    assert(
      typeof obj.id === "number",
      `Object ${i} should have numeric id, got ${typeof obj.id}`,
    );
    assert(
      typeof obj.timestamp === "number",
      `Object ${i} should have numeric timestamp, got ${typeof obj.timestamp}`,
    );
    assert(
      obj.type === "test_message",
      `Object ${i} should have type "test_message", got "${obj.type}"`,
    );
    assert(obj.data, `Object ${i} should have data property`);
    assert(
      typeof obj.data.index === "number",
      `Object ${i} should have numeric data.index`,
    );
    assert(
      typeof obj.data.hash === "string",
      `Object ${i} should have string data.hash`,
    );
    assert(obj.metadata, `Object ${i} should have metadata property`);
    assert(
      obj.metadata.version === "1.0.0",
      `Object ${i} should have metadata.version "1.0.0"`,
    );
  }

  // Verify objects are in order (id should match index)
  for (let i = 0; i < this.parsedObjects.length; i++) {
    assert.strictEqual(
      this.parsedObjects[i].id,
      i,
      `Object at index ${i} should have id ${i}, got ${this.parsedObjects[i].id}`,
    );
  }
});
