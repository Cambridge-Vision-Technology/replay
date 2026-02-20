import { Given, When, Then } from "@cucumber/cucumber";
import assert from "assert";
import path from "path";

// Test state stored on the world object:
// this.testUrls - array of URLs used in the test
// this.playbackResponses - map of url -> response envelope from playback phase
// this.identicalPlaybackResponses - array of response envelopes for identical requests
// this.interceptResponsePayload - the payload the intercept should return
// this.sessionId - the session ID used for session-based connections
// this.controlWs - the WebSocket connection for control channel operations
// this.interceptId - the registered intercept's ID

function buildCommandOpenEnvelope(url, streamIdSuffix) {
  const streamId = `stream-${streamIdSuffix || Date.now()}-${Math.random().toString(36).substring(7)}`;
  return {
    streamId,
    traceId: `trace-${streamId}`,
    causationStreamId: null,
    parentStreamId: null,
    siblingIndex: 0,
    eventSeq: 0,
    timestamp: new Date().toISOString(),
    channel: "program",
    payloadHash: null,
    payload: {
      type: "open",
      payload: {
        service: "http",
        payload: {
          method: "GET",
          url,
          headers: {},
          body: null,
        },
      },
    },
  };
}

function buildInterceptCommand(
  service,
  urlContains,
  responsePayload,
  times = null,
) {
  return {
    command: "register_intercept",
    spec: {
      match: {
        service,
        urlMatch: {
          type: "contains",
          value: urlContains,
        },
      },
      response: {
        service,
        payload: responsePayload,
      },
      priority: 10,
      times,
      delay: null,
    },
  };
}

// ---------------------------------------------------------------------------
// Given steps
// ---------------------------------------------------------------------------

Given(
  "I record a session with an HTTP request to {string}",
  async function (url) {
    this.testUrls = [url];
    this.interceptResponsePayload = {
      intercepted: true,
      source: "intercept",
      url,
    };
    this.playbackResponses = {};

    // Record through the harness so the fixture has PureScript-computed hashes
    await this.createTempWorkspace();
    const recordingPath = path.join(this.workspace, "platform-recording.json");
    await this.startHarness("record", recordingPath);

    const recordSessionId = `record-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const controlWs = await this.connectToHarness();

    const createResult = await this.sendControlCommand(controlWs, {
      command: "create_session",
      config: {
        sessionId: recordSessionId,
        mode: "record",
        recordingPath: this.recordingPath,
      },
    });
    assert(
      createResult.success,
      `Failed to create record session: ${JSON.stringify(createResult)}`,
    );

    // Register an intercept to provide a response without needing a real platform
    const sessionControlWs = await this.connectToHarness(recordSessionId);
    const recordingResponse = {
      status: 200,
      url,
      source: "recording",
      requestIndex: 0,
    };
    const interceptCmd = buildInterceptCommand("http", url, recordingResponse);
    const interceptResult = await this.sendControlCommand(
      sessionControlWs,
      interceptCmd,
    );
    assert(
      interceptResult.success,
      `Failed to register record intercept: ${JSON.stringify(interceptResult)}`,
    );
    this.closeWs(sessionControlWs);

    // Send the request through the harness (intercepted and recorded)
    const programWs = await this.connectToHarness(recordSessionId);
    const commandEnvelope = buildCommandOpenEnvelope(url, "record-0");
    await this.sendAndReceive(programWs, commandEnvelope);
    this.closeWs(programWs);

    // Stop the harness to flush the recording file
    this.closeWs(controlWs);
    await this.stopHarness();
  },
);

Given(
  "I record a session with {int} identical requests to {string}",
  async function (count, url) {
    this.testUrls = Array(count).fill(url);
    this.interceptResponsePayload = {
      intercepted: true,
      source: "intercept",
      url,
    };
    this.playbackResponses = {};

    // Record through the harness so the fixture has PureScript-computed hashes
    await this.createTempWorkspace();
    const recordingPath = path.join(this.workspace, "platform-recording.json");
    await this.startHarness("record", recordingPath);

    const recordSessionId = `record-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const controlWs = await this.connectToHarness();

    const createResult = await this.sendControlCommand(controlWs, {
      command: "create_session",
      config: {
        sessionId: recordSessionId,
        mode: "record",
        recordingPath: this.recordingPath,
      },
    });
    assert(
      createResult.success,
      `Failed to create record session: ${JSON.stringify(createResult)}`,
    );

    // Register an intercept to provide responses without needing a real platform
    const sessionControlWs = await this.connectToHarness(recordSessionId);
    const recordingResponse = { status: 200, url, source: "recording" };
    const interceptCmd = buildInterceptCommand("http", url, recordingResponse);
    const interceptResult = await this.sendControlCommand(
      sessionControlWs,
      interceptCmd,
    );
    assert(
      interceptResult.success,
      `Failed to register record intercept: ${JSON.stringify(interceptResult)}`,
    );
    this.closeWs(sessionControlWs);

    // Send N identical requests through the harness (intercepted and recorded)
    for (let i = 0; i < count; i++) {
      const programWs = await this.connectToHarness(recordSessionId);
      const commandEnvelope = buildCommandOpenEnvelope(url, `record-${i}`);
      await this.sendAndReceive(programWs, commandEnvelope);
      this.closeWs(programWs);
    }

    // Stop the harness to flush the recording file
    this.closeWs(controlWs);
    await this.stopHarness();
  },
);

Given("I restart the harness in playback mode", async function () {
  // Start harness in playback mode, reusing the recording path from the record phase
  await this.startHarness("playback", this.recordingPath);

  // Create a session in playback mode so we get both recorder and player.
  // The session-based flow in Session.purs creates a recorder in playback mode
  // (needed for control API queries) and loads the recording into a player.
  this.sessionId = `playback-${Date.now()}-${Math.random().toString(36).substring(7)}`;

  // Connect control WebSocket (no session param for top-level control commands)
  this.controlWs = await this.connectToHarness();

  const createSessionCmd = {
    command: "create_session",
    config: {
      sessionId: this.sessionId,
      mode: "playback",
      recordingPath: this.recordingPath,
    },
  };
  const createResult = await this.sendControlCommand(
    this.controlWs,
    createSessionCmd,
  );
  assert(
    createResult.success,
    `Failed to create playback session: ${JSON.stringify(createResult)}`,
  );
});

Given(
  "I register an intercept for service {string} matching url {string}",
  async function (service, urlContains) {
    // Register intercept via the session's control channel
    const sessionControlWs = await this.connectToHarness(this.sessionId);

    const interceptCmd = buildInterceptCommand(
      service,
      urlContains,
      this.interceptResponsePayload,
    );
    const result = await this.sendControlCommand(
      sessionControlWs,
      interceptCmd,
    );
    assert(
      result.success,
      `Failed to register intercept: ${JSON.stringify(result)}`,
    );
    assert(
      result.payload && result.payload.interceptId,
      `Expected interceptId in response: ${JSON.stringify(result)}`,
    );

    this.interceptId = result.payload.interceptId;
    this.closeWs(sessionControlWs);
  },
);

Given(
  "I register an intercept for service {string} matching url {string} with times {int}",
  async function (service, urlContains, times) {
    const sessionControlWs = await this.connectToHarness(this.sessionId);

    const interceptCmd = buildInterceptCommand(
      service,
      urlContains,
      this.interceptResponsePayload,
      times,
    );

    const result = await this.sendControlCommand(
      sessionControlWs,
      interceptCmd,
    );
    assert(
      result.success,
      `Failed to register intercept: ${JSON.stringify(result)}`,
    );
    assert(
      result.payload && result.payload.interceptId,
      `Expected interceptId in response: ${JSON.stringify(result)}`,
    );

    this.interceptId = result.payload.interceptId;
    this.closeWs(sessionControlWs);
  },
);

// ---------------------------------------------------------------------------
// When steps
// ---------------------------------------------------------------------------

When("I replay the same HTTP request to {string}", async function (url) {
  const programWs = await this.connectToHarness(this.sessionId);

  const commandEnvelope = buildCommandOpenEnvelope(url, "playback-1");
  const response = await this.sendAndReceive(programWs, commandEnvelope);

  this.playbackResponses[url] = response;
  this.closeWs(programWs);
});

When(
  "I replay {int} identical requests to {string}",
  async function (count, url) {
    this.identicalPlaybackResponses = [];

    for (let i = 0; i < count; i++) {
      const programWs = await this.connectToHarness(this.sessionId);

      const commandEnvelope = buildCommandOpenEnvelope(
        url,
        `playback-identical-${i}`,
      );
      const response = await this.sendAndReceive(programWs, commandEnvelope);

      this.identicalPlaybackResponses.push(response);
      this.closeWs(programWs);
    }
  },
);

// ---------------------------------------------------------------------------
// Then steps
// ---------------------------------------------------------------------------

Then("the response should come from the intercept", function () {
  const url = this.testUrls[0];
  const response = this.playbackResponses[url];

  assert(response, `No playback response received for ${url}`);

  // The response should not be an error
  assert(
    !response.error,
    `Received error response: ${JSON.stringify(response)}`,
  );

  // The response should contain the intercept's payload
  const payload = this.extractResponsePayload(response);
  assert(
    payload,
    `Could not extract response payload from: ${JSON.stringify(response)}`,
  );

  assert.strictEqual(
    payload.intercepted,
    true,
    `Expected intercept response (intercepted: true), got: ${JSON.stringify(payload)}`,
  );
  assert.strictEqual(
    payload.source,
    "intercept",
    `Expected source "intercept", got: ${JSON.stringify(payload)}`,
  );
});

Then("the first response should come from the intercept", function () {
  assert(
    this.identicalPlaybackResponses,
    "No identical playback responses recorded",
  );
  assert(
    this.identicalPlaybackResponses.length > 0,
    "Expected at least one response",
  );

  const response = this.identicalPlaybackResponses[0];

  assert(response, "No response received for the first request");
  assert(
    !response.error,
    `Received error response for the first request: ${JSON.stringify(response)}`,
  );

  const payload = this.extractResponsePayload(response);
  assert(
    payload,
    `Could not extract response payload for the first request: ${JSON.stringify(response)}`,
  );

  assert.strictEqual(
    payload.intercepted,
    true,
    `Expected intercept response for the first request (intercepted: true), got: ${JSON.stringify(payload)}`,
  );
  assert.strictEqual(
    payload.source,
    "intercept",
    `Expected source "intercept" for the first request, got: ${JSON.stringify(payload)}`,
  );
});

Then(
  "the remaining {int} responses should come from the recording",
  function (count) {
    assert(
      this.identicalPlaybackResponses,
      "No identical playback responses recorded",
    );

    const totalResponses = this.identicalPlaybackResponses.length;
    assert(
      totalResponses > count,
      `Expected more than ${count} total responses to have ${count} remaining, got ${totalResponses}`,
    );

    // Check responses starting from index 1 (after the first intercepted one)
    for (let i = 1; i <= count; i++) {
      const response = this.identicalPlaybackResponses[i];

      assert(response, `No response received for request ${i + 1}`);
      assert(
        !response.error,
        `Received error response for request ${i + 1}: ${JSON.stringify(response)}`,
      );

      const payload = this.extractResponsePayload(response);
      assert(
        payload,
        `Could not extract response payload for request ${i + 1}: ${JSON.stringify(response)}`,
      );

      // The response should NOT have the intercept marker
      assert.notStrictEqual(
        payload.intercepted,
        true,
        `Expected recorded response for request ${i + 1}, but got intercept response: ${JSON.stringify(payload)}`,
      );

      assert.strictEqual(
        payload.source,
        "recording",
        `Expected source "recording" for request ${i + 1}, got: ${JSON.stringify(payload)}`,
      );
    }
  },
);

Then(
  "the first {int} responses should come from the intercept",
  function (count) {
    assert(
      this.identicalPlaybackResponses,
      "No identical playback responses recorded",
    );
    assert(
      this.identicalPlaybackResponses.length >= count,
      `Expected at least ${count} responses, got ${this.identicalPlaybackResponses.length}`,
    );

    for (let i = 0; i < count; i++) {
      const response = this.identicalPlaybackResponses[i];

      assert(response, `No response received for request ${i + 1}`);
      assert(
        !response.error,
        `Received error response for request ${i + 1}: ${JSON.stringify(response)}`,
      );

      const payload = this.extractResponsePayload(response);
      assert(
        payload,
        `Could not extract response payload for request ${i + 1}: ${JSON.stringify(response)}`,
      );

      assert.strictEqual(
        payload.intercepted,
        true,
        `Expected intercept response for request ${i + 1} (intercepted: true), got: ${JSON.stringify(payload)}`,
      );
      assert.strictEqual(
        payload.source,
        "intercept",
        `Expected source "intercept" for request ${i + 1}, got: ${JSON.stringify(payload)}`,
      );
    }
  },
);

Then("the last response should come from the recording", function () {
  assert(
    this.identicalPlaybackResponses,
    "No identical playback responses recorded",
  );
  assert(
    this.identicalPlaybackResponses.length > 0,
    "Expected at least one response",
  );

  const response =
    this.identicalPlaybackResponses[this.identicalPlaybackResponses.length - 1];

  assert(response, "No response received for the last request");
  assert(
    !response.error,
    `Received error response for the last request: ${JSON.stringify(response)}`,
  );

  const payload = this.extractResponsePayload(response);
  assert(
    payload,
    `Could not extract response payload for the last request: ${JSON.stringify(response)}`,
  );

  assert.notStrictEqual(
    payload.intercepted,
    true,
    `Expected recorded response for the last request, but got intercept response: ${JSON.stringify(payload)}`,
  );
  assert.strictEqual(
    payload.source,
    "recording",
    `Expected source "recording" for the last request, got: ${JSON.stringify(payload)}`,
  );
});

Then("the harness should still be operational", async function () {
  // Verify the harness hasn't crashed by sending a control command
  // Use the session's control channel to query status
  const sessionControlWs = await this.connectToHarness(this.sessionId);

  const statusCmd = { command: "get_status" };
  const statusResult = await this.sendControlCommand(
    sessionControlWs,
    statusCmd,
  );

  assert(
    statusResult.success,
    `Harness status query failed (harness may have crashed): ${JSON.stringify(statusResult)}`,
  );

  assert(
    statusResult.payload && statusResult.payload.response === "status",
    `Expected status response, got: ${JSON.stringify(statusResult)}`,
  );

  this.closeWs(sessionControlWs);

  // Also clean up the main control WebSocket
  this.closeWs(this.controlWs);
  this.controlWs = null;
});
