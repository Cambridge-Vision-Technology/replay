import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import { promises as fs } from "fs";
import path from "path";

Given("the replay server is running in record mode", async function () {
  await this.startHarness("record");
});

Given("the replay server is running in playback mode", async function () {
  await this.startHarness("playback");
});

Given(
  "I have a recording of echo-client with message {string}",
  async function (message) {
    const recordingPath = this.getRecordingPath();
    const exists = await this.fileExists(recordingPath);

    if (!exists) {
      const compressedPath = recordingPath.replace(".json", ".json.zstd");
      const compressedExists = await this.fileExists(compressedPath);
      assert(
        compressedExists,
        `Recording fixture not found at: ${recordingPath} or ${compressedPath}. ` +
          `Run 'nix run .#test-record' first to create the fixture.`,
      );
    }
  },
);

Given("I have a recording fixture", async function () {
  const recordingPath = this.getRecordingPath();
  const exists = await this.fileExists(recordingPath);

  if (!exists) {
    const compressedPath = recordingPath.replace(".json", ".json.zstd");
    const compressedExists = await this.fileExists(compressedPath);
    assert(
      compressedExists,
      `Recording fixture not found at: ${recordingPath} or ${compressedPath}. ` +
        `Playback tests require pre-recorded fixtures.`,
    );
  }
});

When(
  "I run echo-client directly with message {string}",
  async function (message) {
    await this.runEchoClientDirect(message);
  },
);

When("I run echo-client with message {string}", async function (message) {
  await this.runEchoClient(message);
});

Then("the exit code should be {int}", function (expectedCode) {
  assert.strictEqual(
    this.lastCommandResult.code,
    expectedCode,
    `Expected exit code ${expectedCode}, got ${this.lastCommandResult.code}. ` +
      `Output: ${this.lastCommandResult.output}`,
  );
});

Then("the output should contain {string}", function (expectedText) {
  const output = this.lastCommandResult.output;
  assert(
    output.includes(expectedText),
    `Expected output to contain "${expectedText}". Actual output: ${output}`,
  );
});

Then("a recording file should exist", async function () {
  await this.stopHarness();

  const recordingPath = this.getRecordingPath();
  const compressedPath = recordingPath.replace(".json", ".json.zstd");

  const uncompressedExists = await this.fileExists(recordingPath);
  const compressedExists = await this.fileExists(compressedPath);

  assert(
    uncompressedExists || compressedExists,
    `Recording file not found at: ${recordingPath} or ${compressedPath}`,
  );
});

Then("the recording should contain the HTTP request", async function () {
  const recordingPath = this.getRecordingPath();
  const compressedPath = recordingPath.replace(".json", ".json.zstd");

  let recording;

  if (await this.fileExists(recordingPath)) {
    recording = await this.readJsonFile(recordingPath);
  } else if (await this.fileExists(compressedPath)) {
    const { promisify } = await import("util");
    const zstd = await import("zstd-napi");
    const compressed = await fs.readFile(compressedPath);
    const decompressed = zstd.decompress(compressed);
    recording = JSON.parse(decompressed.toString("utf8"));
  } else {
    throw new Error(
      `Recording not found at ${recordingPath} or ${compressedPath}`,
    );
  }

  assert(recording.messages, "Recording should have messages array");
  assert(
    recording.messages.length > 0,
    "Recording should have at least one message",
  );

  const httpMessages = recording.messages.filter((msg) => {
    const envelope = msg.envelope;
    if (!envelope || !envelope.payload) return false;

    if (envelope.payload.tag === "CommandOpen") {
      const requestPayload = envelope.payload.contents;
      return requestPayload && requestPayload.service === "http";
    }
    return false;
  });

  assert(
    httpMessages.length > 0,
    `Expected HTTP request in recording, but found only: ${recording.messages.map((m) => m.envelope?.payload?.tag || "unknown").join(", ")}`,
  );
});

Then("the output should match the recorded response", async function () {
  assert(
    this.lastCommandResult.success,
    `Echo client failed: ${this.lastCommandResult.output}`,
  );

  const output = this.lastCommandResult.stdout;
  assert(
    output.includes("httpbin.org") ||
      output.includes("json") ||
      output.includes("method"),
    `Expected output to contain httpbin response data. Actual: ${output}`,
  );
});

Then("the harness should be accepting connections", async function () {
  assert(this.harnessSocketPath, "Harness socket path should be set");

  const socketExists = await this.fileExists(this.harnessSocketPath);
  assert(
    socketExists,
    `Harness socket should exist at: ${this.harnessSocketPath}`,
  );
});
