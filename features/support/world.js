import {
  setWorldConstructor,
  After,
  Before,
  setDefaultTimeout,
} from "@cucumber/cucumber";
import { spawn, spawnSync } from "child_process";
import { promises as fs } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

setDefaultTimeout(30000);

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

class ReplayWorld {
  constructor() {
    this.projectRoot = process.cwd();
    this.pickle = null;
    this.lastCommandResult = null;
    this.workspace = null;
    this.fixturesPath = null;
    this.harnessProcess = null;
    this.harnessSocketPath = null;
    this.recordingPath = null;
  }

  getSanitizedScenarioName() {
    if (!this.pickle || !this.pickle.name) {
      throw new Error("No pickle/name available - cannot determine scenario");
    }
    return this.pickle.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
  }

  getFeatureName() {
    if (!this.pickle || !this.pickle.uri) {
      throw new Error("No pickle/URI available - cannot determine feature");
    }
    return path.basename(this.pickle.uri, ".feature");
  }

  async createTempWorkspace() {
    if (!this.workspace) {
      const scenario = this.getSanitizedScenarioName();
      const workspaceDir = path.join(this.projectRoot, "out", "test", scenario);
      await fs.mkdir(workspaceDir, { recursive: true });
      this.workspace = workspaceDir;

      const featureName = this.getFeatureName();
      const scenarioName = this.getSanitizedScenarioName();
      this.fixturesPath = path.join(
        this.projectRoot,
        "features",
        "fixtures",
        featureName,
        scenarioName,
        "files",
      );
    }
    return this.workspace;
  }

  getRecordingPath() {
    const featureName = this.getFeatureName();
    const scenarioName = this.getSanitizedScenarioName();
    return path.join(
      this.projectRoot,
      "features",
      "fixtures",
      featureName,
      scenarioName,
      "files",
      "platform-recording.json",
    );
  }

  async startHarness(mode) {
    const harnessBinary = process.env.REPLAY_HARNESS_BINARY || "replay";
    const tmpDir = process.env.TMPDIR || "/tmp";
    const uniqueId = `${Date.now()}-${Math.random().toString(36).substring(7)}`;
    this.harnessSocketPath = path.join(tmpDir, `replay-test-${uniqueId}.sock`);
    this.recordingPath = this.getRecordingPath();

    if (mode === "record") {
      const fixtureDir = path.dirname(this.recordingPath);
      await fs.mkdir(fixtureDir, { recursive: true });
    }

    const args = [
      "--mode",
      mode,
      "--socket",
      this.harnessSocketPath,
      "--recording-path",
      this.recordingPath,
    ];

    return new Promise((resolve, reject) => {
      this.harnessProcess = spawn(harnessBinary, args, {
        stdio: ["ignore", "pipe", "pipe"],
        env: { ...process.env },
      });

      let stdout = "";
      let stderr = "";
      let resolved = false;

      const timeoutId = setTimeout(() => {
        if (!resolved) {
          resolved = true;
          reject(
            new Error(
              `Harness failed to start within timeout. stdout: ${stdout}, stderr: ${stderr}`,
            ),
          );
        }
      }, 30000);

      this.harnessProcess.stdout.on("data", (data) => {
        stdout += data.toString();
        if (stdout.includes("Harness server listening") && !resolved) {
          resolved = true;
          clearTimeout(timeoutId);
          setTimeout(() => resolve(this.harnessSocketPath), 500);
        }
      });

      this.harnessProcess.stderr.on("data", (data) => {
        stderr += data.toString();
      });

      this.harnessProcess.on("error", (err) => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timeoutId);
          reject(err);
        }
      });

      this.harnessProcess.on("exit", (code) => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timeoutId);
          reject(
            new Error(
              `Harness exited with code ${code}. stdout: ${stdout}, stderr: ${stderr}`,
            ),
          );
        }
      });
    });
  }

  async stopHarness() {
    if (this.harnessProcess) {
      this.harnessProcess.kill("SIGTERM");
      await new Promise((resolve) => setTimeout(resolve, 2000));
      if (!this.harnessProcess.killed) {
        this.harnessProcess.kill("SIGKILL");
      }
      this.harnessProcess = null;
    }

    if (this.harnessSocketPath) {
      try {
        await fs.unlink(this.harnessSocketPath);
      } catch {
        // Ignore if socket doesn't exist
      }
      this.harnessSocketPath = null;
    }
  }

  async runEchoClientDirect(message) {
    return new Promise((resolve) => {
      const echoClientBinary = process.env.ECHO_CLIENT_BINARY || "echo-client";

      const result = spawnSync(echoClientBinary, [message], {
        encoding: "utf8",
        env: process.env,
        maxBuffer: 10 * 1024 * 1024,
      });

      this.lastCommandResult = {
        code: result.status ?? 1,
        stdout: result.stdout || "",
        stderr: result.stderr || "",
        output: (result.stdout || "") + (result.stderr || ""),
        success: result.status === 0,
      };

      resolve(this.lastCommandResult);
    });
  }

  async runEchoClient(message, options = {}) {
    return new Promise((resolve) => {
      const echoClientBinary = process.env.ECHO_CLIENT_BINARY || "echo-client";

      const env = { ...process.env, ...options.env };
      if (this.harnessSocketPath) {
        env.PLATFORM_URL = this.harnessSocketPath;
      }

      const result = spawnSync(echoClientBinary, [message], {
        encoding: "utf8",
        env,
        maxBuffer: 10 * 1024 * 1024,
      });

      this.lastCommandResult = {
        code: result.status ?? 1,
        stdout: result.stdout || "",
        stderr: result.stderr || "",
        output: (result.stdout || "") + (result.stderr || ""),
        success: result.status === 0,
      };

      resolve(this.lastCommandResult);
    });
  }

  async createMinimalRecordingFixture() {
    const recordingPath = this.getRecordingPath();
    const fixtureDir = path.dirname(recordingPath);
    await fs.mkdir(fixtureDir, { recursive: true });

    const minimalRecording = {
      version: "1.0.0",
      messages: [],
    };

    await fs.writeFile(
      recordingPath,
      JSON.stringify(minimalRecording, null, 2),
    );
    this.recordingPath = recordingPath;
  }

  async fileExists(filePath) {
    try {
      await fs.access(filePath);
      return true;
    } catch {
      return false;
    }
  }

  async readJsonFile(filePath) {
    const content = await fs.readFile(filePath, "utf8");
    return JSON.parse(content);
  }

  async cleanupWorkspace() {
    if (this.workspace) {
      this.workspace = null;
    }
  }
}

setWorldConstructor(ReplayWorld);

Before(async function (testCaseHookParameter) {
  this.pickle = testCaseHookParameter.pickle;
});

After({ timeout: 60000 }, async function () {
  await this.stopHarness();
  await this.cleanupWorkspace();
});
