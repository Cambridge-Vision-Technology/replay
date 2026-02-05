import { promises as fs } from "fs";
import path from "path";
import assert from "assert";
import { spawn } from "child_process";
import { connect } from "net";

let globalHarnessProcess = null;
let globalHarnessSocket = null;
let usingExternalHarness = false;

export const getGlobalHarnessSocket = () => globalHarnessSocket;

export const waitForHarnessReady = async (socketPath, timeoutMs) => {
  const start = Date.now();

  while (Date.now() - start < timeoutMs) {
    try {
      await fs.access(socketPath);
      break;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }

  try {
    await fs.access(socketPath);
  } catch {
    return false;
  }

  const { default: WebSocket } = await import("ws");

  let retryDelay = 200;
  while (Date.now() - start < timeoutMs) {
    try {
      const ws = new WebSocket("ws://unix-socket/", {
        createConnection: () => connect(socketPath),
      });
      await new Promise((resolve, reject) => {
        ws.on("open", () => {
          ws.close();
          resolve();
        });
        ws.on("error", (err) => {
          reject(err);
        });
        setTimeout(() => reject(new Error("Connection timeout")), 2000);
      });
      return true;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, retryDelay));
      retryDelay = Math.min(retryDelay * 1.5, 2000);
    }
  }
  return false;
};

export const startGlobalHarness = async (options = {}) => {
  const {
    harnessBinary = process.env.REPLAY_HARNESS_BINARY || "replay",
    mode = "playback",
    recordingDir = path.join(process.cwd(), "features/fixtures"),
    startupTimeoutMs = 120000,
    connectTimeoutMs = 15000,
    socketPath = null,
  } = options;

  const externalSocketPath = process.env.GLOBAL_HARNESS_SOCKET;

  if (externalSocketPath) {
    try {
      await fs.access(externalSocketPath);
    } catch {
      throw new Error(
        `GLOBAL_HARNESS_SOCKET is set to "${externalSocketPath}" but socket file does not exist. ` +
          `Ensure the external harness is started before running tests.`,
      );
    }

    const jitter = Math.floor(Math.random() * 3000);
    await new Promise((resolve) => setTimeout(resolve, jitter));

    const canConnect = await waitForHarnessReady(externalSocketPath, 30000);
    if (!canConnect) {
      throw new Error(
        `GLOBAL_HARNESS_SOCKET is set to "${externalSocketPath}" and socket exists, ` +
          `but cannot establish WebSocket connection. Is the harness running?`,
      );
    }

    globalHarnessSocket = externalSocketPath;
    usingExternalHarness = true;
    if (process.env.DEBUG_HARNESS) {
      console.log(`Using external harness at socket: ${globalHarnessSocket}`);
    }
    return { socketPath: globalHarnessSocket, external: true };
  }

  const tmpDir = process.env.TMPDIR || "/tmp";
  globalHarnessSocket =
    socketPath || path.join(tmpDir, `replay-harness-${Date.now()}.sock`);

  const args = [
    "--mode",
    mode,
    "--socket",
    globalHarnessSocket,
    "--recording-dir",
    recordingDir,
  ];

  globalHarnessProcess = spawn(harnessBinary, args, {
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env },
  });

  let stdout = "";
  let stderr = "";
  let exitCode = null;
  let exitSignal = null;
  let spawnError = null;

  globalHarnessProcess.on("error", (err) => {
    spawnError = err;
  });

  const harnessReady = await new Promise((resolve) => {
    const timeoutId = setTimeout(() => {
      globalHarnessProcess.kill("SIGTERM");
      resolve(false);
    }, startupTimeoutMs);

    globalHarnessProcess.stdout.on("data", (data) => {
      stdout += data.toString();
      if (process.env.DEBUG_HARNESS) {
        console.log(`[harness stdout] ${data.toString().trim()}`);
      }
      if (stdout.includes("Harness server listening")) {
        clearTimeout(timeoutId);
        resolve(true);
      }
    });

    globalHarnessProcess.stderr.on("data", (data) => {
      stderr += data.toString();
      if (process.env.DEBUG_HARNESS) {
        console.log(`[harness stderr] ${data.toString().trim()}`);
      }
    });

    globalHarnessProcess.on("exit", (code, signal) => {
      exitCode = code;
      exitSignal = signal;
      clearTimeout(timeoutId);
      resolve(false);
    });
  });

  if (!harnessReady) {
    throw new Error(
      `Global harness failed to start. Binary: ${harnessBinary}, args: ${JSON.stringify(args)}, exitCode: ${exitCode}, signal: ${exitSignal}, spawnError: ${spawnError}, stdout: ${stdout}, stderr: ${stderr}`,
    );
  }

  await new Promise((resolve) => setTimeout(resolve, 500));

  const canConnect = await waitForHarnessReady(
    globalHarnessSocket,
    connectTimeoutMs,
  );
  if (!canConnect) {
    throw new Error(
      `Global harness reported listening but cannot connect to socket ${globalHarnessSocket}. stdout: ${stdout}, stderr: ${stderr}`,
    );
  }

  if (process.env.DEBUG_HARNESS) {
    console.log(`Global harness started on socket: ${globalHarnessSocket}`);
  }

  return { socketPath: globalHarnessSocket, external: false };
};

export const stopGlobalHarness = async () => {
  if (usingExternalHarness) {
    if (process.env.DEBUG_HARNESS) {
      console.log(
        `Skipping harness cleanup - using external harness at: ${globalHarnessSocket}`,
      );
    }
    return;
  }

  if (globalHarnessProcess) {
    globalHarnessProcess.kill("SIGTERM");
    await new Promise((resolve) => setTimeout(resolve, 2000));
    if (!globalHarnessProcess.killed) {
      globalHarnessProcess.kill("SIGKILL");
    }
    globalHarnessProcess = null;
  }

  if (globalHarnessSocket) {
    try {
      await fs.unlink(globalHarnessSocket);
    } catch {
      // Ignore if socket doesn't exist
    }
    globalHarnessSocket = null;
  }
};

export const checkRecordingExists = async (recordingPath) => {
  const compressedPath = recordingPath.replace(".json", ".json.zstd");
  const [uncompressedExists, compressedExists] = await Promise.all([
    fs
      .access(recordingPath)
      .then(() => true)
      .catch(() => false),
    fs
      .access(compressedPath)
      .then(() => true)
      .catch(() => false),
  ]);
  return {
    exists: uncompressedExists || compressedExists,
    compressedPath,
    uncompressedExists,
    compressedExists,
  };
};

export const createSessionForCommand = async (
  world,
  commandName,
  options = {},
) => {
  const globalSocketPath = getGlobalHarnessSocket();
  if (!globalSocketPath) {
    throw new Error("Global harness not started - no socket available");
  }

  world.currentHarnessSocketPath = globalSocketPath;

  const scenarioName = world.getSanitizedScenarioName();
  const sessionId = `${commandName}-${scenarioName}-${Date.now()}`;

  let featureName = options.featureName;
  if (!featureName && world.pickle && world.pickle.uri) {
    featureName = path.basename(world.pickle.uri, ".feature");
  } else if (!featureName) {
    featureName = `${commandName}_platform`;
  }
  const fixturePath = `${featureName}/${scenarioName}`;
  const recordingPath = world.getRecordingPath(fixturePath);

  const testMode = process.env.REPLAY_TEST_MODE || "playback";
  const isPlayback = testMode === "playback";
  if (options.optional && isPlayback) {
    const { exists } = await checkRecordingExists(recordingPath);
    if (!exists) {
      return null;
    }
  }

  await world.createSession({
    sessionId,
    recordingPath,
    mode: options.mode,
  });

  world.currentSessionId = sessionId;
  world.currentRecordingPath = recordingPath;
  return sessionId;
};

export const closeSessionForCommand = async (world) => {
  if (world.currentSessionId) {
    await world.closeSession(world.currentSessionId);
    world.currentSessionId = null;
    world.currentRecordingPath = null;
  }
};

export const getSessionPlatformUrl = (world) => {
  const socketPath = getGlobalHarnessSocket();
  if (!socketPath) {
    throw new Error("Global harness not started - no socket available");
  }
  if (!world.currentSessionId) {
    throw new Error("No session created - call createSessionForCommand first");
  }
  return `unix:${socketPath}?session=${encodeURIComponent(world.currentSessionId)}`;
};

export const copyFixtureFilesRecursive = async (src, dest) => {
  const stat = await fs.stat(src);
  if (stat.isDirectory()) {
    await fs.mkdir(dest, { recursive: true });
    const entries = await fs.readdir(src);
    for (const entry of entries) {
      if (
        entry === "platform-recording.json" ||
        entry === "platform-recording.json.zstd"
      )
        continue;
      await copyFixtureFilesRecursive(
        path.join(src, entry),
        path.join(dest, entry),
      );
    }
  } else {
    await fs.copyFile(src, dest);
  }
};

export const initializeWorkspaceFromFixtures = async (world, commandName) => {
  await world.createTempWorkspace({ skipFixtures: true });
  const scenarioName = world.getSanitizedScenarioName();
  const fixturePath = `${commandName}_platform/${scenarioName}`;
  const fixtureDir = path.join(
    process.cwd(),
    "features/fixtures",
    fixturePath,
    "files",
  );
  await copyFixtureFilesRecursive(fixtureDir, world.workspace);
};

export const startPlatformHarnessForCommand = async (
  world,
  commandName,
  scenarioName,
) => {
  const testMode = process.env.REPLAY_TEST_MODE || "playback";
  const isRecording = ["live", "record"].includes(testMode);
  const mode = isRecording ? "record" : "playback";

  const fixturePath = `${commandName}_platform/${scenarioName}`;
  const recordingPath = world.getRecordingPath(fixturePath);

  console.log(`Starting ${commandName} platform harness in ${mode} mode...`);
  console.log(`Recording path: ${recordingPath}`);

  const { process: harnessProcess, socketPath } = await world.startHarness({
    mode,
    recordingPath,
  });

  return { harnessProcess, socketPath };
};

export const assertRecordingFixtureExists = async (fixturePath) => {
  const projectRoot = process.cwd();
  const recordingPath = path.join(
    projectRoot,
    "features/fixtures",
    fixturePath,
    "files/platform-recording.json",
  );
  const { exists, compressedPath } = await checkRecordingExists(recordingPath);
  assert(
    exists,
    `Recording fixture not found at: ${recordingPath} or ${compressedPath}`,
  );
};

export const assertRecordingHasMinMessages = async (
  recordingPath,
  minMessages,
) => {
  assert(recordingPath, "No recording fixture path set");

  let content;
  const { compressedExists } = await checkRecordingExists(recordingPath);
  const compressedPath = recordingPath.replace(".json", ".json.zstd");

  if (compressedExists) {
    const { decompress } = await import("zstd-napi");
    const compressed = await fs.readFile(compressedPath);
    const decompressed = await decompress(compressed);
    content = decompressed.toString("utf8");
  } else {
    content = await fs.readFile(recordingPath, "utf8");
  }

  const recording = JSON.parse(content);
  assert(
    recording.messages && recording.messages.length >= minMessages,
    `Recording should have at least ${minMessages} messages, but has ${recording.messages?.length || 0}`,
  );
};

export const connectControl = async (socketPath, sessionId = null) => {
  const { default: WebSocket } = await import("ws");

  return new Promise((resolve, reject) => {
    const wsUrl = sessionId
      ? `ws://unix-socket/?session=${encodeURIComponent(sessionId)}`
      : "ws://unix-socket/";

    const ws = new WebSocket(wsUrl, {
      createConnection: () => connect(socketPath),
    });

    ws.on("open", () => {
      resolve(ws);
    });

    ws.on("error", (err) => {
      reject(new Error(`Control connection failed: ${err.message}`));
    });

    setTimeout(() => {
      reject(new Error("Control connection timeout after 5000ms"));
    }, 5000);
  });
};

export const sendControlCommand = async (ws, command, timeoutMs = 5000) => {
  const requestId = `req-${Date.now()}-${Math.random().toString(36).substring(7)}`;

  const envelope = {
    channel: "control",
    requestId,
    payload: command,
  };

  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error(`Control command timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    const messageHandler = (data) => {
      try {
        const response = JSON.parse(data.toString());
        if (response.requestId === requestId) {
          ws.removeListener("message", messageHandler);
          clearTimeout(timeoutId);
          if (response.success === false) {
            reject(
              new Error(`Control error: ${JSON.stringify(response.error)}`),
            );
          } else {
            resolve(response.payload);
          }
        }
      } catch {
        // Ignore non-JSON messages or messages for other requests
      }
    };

    ws.on("message", messageHandler);
    ws.send(JSON.stringify(envelope));
  });
};

export const createCucumberHooks = (cucumberModule, options = {}) => {
  const { BeforeAll, AfterAll } = cucumberModule;
  const {
    harnessBinaryEnvVar = "REPLAY_HARNESS_BINARY",
    testModeEnvVar = "REPLAY_TEST_MODE",
    recordingDir = path.join(process.cwd(), "features/fixtures"),
    startupTimeoutMs = 180000,
  } = options;

  BeforeAll({ timeout: startupTimeoutMs }, async function () {
    const testMode = process.env[testModeEnvVar] || "playback";
    const mode =
      testMode === "live"
        ? "passthrough"
        : testMode === "record"
          ? "record"
          : "playback";

    await startGlobalHarness({
      harnessBinary: process.env[harnessBinaryEnvVar] || "replay",
      mode,
      recordingDir,
      startupTimeoutMs,
    });
  });

  AfterAll(async function () {
    await stopGlobalHarness();
  });
};
