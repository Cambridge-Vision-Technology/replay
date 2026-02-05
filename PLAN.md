# Plan: Extract Test Harness into Standalone "replay" Repository

**Issue**: Cambridge-Vision-Technology/oz#438
**Branch**: `issue-438-extract-harness`

## Overview

Extract the test harness infrastructure from oz into this standalone repository. The replay library provides WebSocket-based recording/playback for deterministic testing of external effects (HTTP, LLM, cloud APIs).

**Key Design Decisions**:

1. **Demo app is the primary testing mechanism** - a real application exercising replay validates it works
2. **Keep unit tests during migration** - safety net until BDD integration tests are trusted
3. **Opaque JSON payloads** - service types are strings, payloads are arbitrary JSON
4. **String secret keys** - no oz-specific dependencies
5. **Separate JS helpers package** - @cvt/replay-helpers for Cucumber integration

**Testing Philosophy**:

- Unit tests verify internal correctness (keep during migration)
- Demo app + BDD features verify user-facing behavior (primary mechanism)
- oz integration validates the extraction didn't break anything

---

## Phase 1: Repository Scaffolding & Infrastructure

### Task 1.1: Initialize flake.nix with CVT tooling

- [ ] Create flake.nix with inputs: purs-nix, whine, dedup, scythe, drop, agen, eslint-plugin-purescript-ffi, purescript-overlay, treefmt-nix
- [ ] Create package.json with dependencies: ws, ulid, zstd-napi
- [ ] Create agents.yaml for CLAUDE.md generation
- [ ] DevShell with all tools, auto-generates CLAUDE.md on entry
- [ ] treefmt config: purs-tidy, prettier, nixfmt
- [ ] Basic .gitignore, .envrc

**Verification**: `nix develop` works, CLAUDE.md generated

---

## Phase 2: Copy Code from oz (Preserve Unit Tests)

### Task 2.1: Copy harness source files

Copy all harness-related code from oz, preserving the existing unit tests as a safety net.

| oz Path                                                | replay Path                            |
| ------------------------------------------------------ | -------------------------------------- |
| `harness/src/Main.purs`                                | `src/Main.purs`                        |
| `harness/src/Signal.purs`                              | `src/Signal.purs`                      |
| `harness/src/Signal.js`                                | `src/Signal.js`                        |
| `src/Testing/Platform/Harness/Server.purs`             | `src/Replay/Server.purs`               |
| `src/Testing/Platform/Harness/Server.js`               | `src/Replay/Server.js`                 |
| `src/Testing/Platform/Harness/Handler.purs`            | `src/Replay/Handler.purs`              |
| `src/Testing/Platform/Harness/Session.purs`            | `src/Replay/Session.purs`              |
| `src/Testing/Platform/Harness/Recorder.purs`           | `src/Replay/Recorder.purs`             |
| `src/Testing/Platform/Harness/Player.purs`             | `src/Replay/Player.purs`               |
| `src/Testing/Platform/Harness/Player/Test.purs`        | `src/Replay/Player/Test.purs`          |
| `src/Testing/Platform/Harness/Interceptor.purs`        | `src/Replay/Interceptor.purs`          |
| `src/Testing/Platform/Harness/IdTranslation.purs`      | `src/Replay/IdTranslation.purs`        |
| `src/Testing/Platform/Harness/IdTranslation/Test.purs` | `src/Replay/IdTranslation/Test.purs`   |
| `src/Testing/Platform/Harness/Types.purs`              | `src/Replay/Types.purs`                |
| `src/Testing/Platform/Harness/Test.purs`               | `src/Replay/Test.purs`                 |
| `src/Testing/Platform/Recording.purs`                  | `src/Replay/Recording.purs`            |
| `src/Testing/Platform/Recording/Test.purs`             | `src/Replay/Recording/Test.purs`       |
| `src/Testing/Platform/Hash.purs`                       | `src/Replay/Hash.purs`                 |
| `src/Testing/Platform/Types.purs`                      | `src/Replay/Protocol/Types.purs`       |
| `src/Testing/Platform/Types/Test.purs`                 | `src/Replay/Protocol/Types/Test.purs`  |
| `src/Testing/Platform/Envelope.purs`                   | `src/Replay/Protocol/Envelope.purs`    |
| `src/Testing/Platform/Common.purs`                     | `src/Replay/Common.purs`               |
| `src/Testing/Platform/Client.purs`                     | `src/Replay/Client.purs`               |
| `src/Testing/Platform/Client.js`                       | `src/Replay/Client.js`                 |
| `src/Testing/Platform/Normalize.purs`                  | `src/Replay/Normalize.purs`            |
| `src/Testing/Platform/Normalize/Test.purs`             | `src/Replay/Normalize/Test.purs`       |
| `src/Testing/Platform/ULID.purs`                       | `src/Replay/ULID.purs`                 |
| `src/Testing/Platform/ULID/Test.purs`                  | `src/Replay/ULID/Test.purs`            |
| `src/Testing/Platform/Stream.purs`                     | `src/Replay/Stream.purs`               |
| `src/Testing/Platform/Stream/Test.purs`                | `src/Replay/Stream/Test.purs`          |
| `src/Testing/Platform/PendingRequests.purs`            | `src/Replay/PendingRequests.purs`      |
| `src/Testing/Platform/PendingRequests/Test.purs`       | `src/Replay/PendingRequests/Test.purs` |
| `src/Testing/Platform/TraceContext.purs`               | `src/Replay/TraceContext.purs`         |
| `src/Testing/Platform/TraceContext/Effect.purs`        | `src/Replay/TraceContext/Effect.purs`  |
| `src/Testing/Platform/TraceContext/Test.purs`          | `src/Replay/TraceContext/Test.purs`    |
| `src/Testing/Platform/Time.purs`                       | `src/Replay/Time.purs`                 |
| `features/support/platform_harness_helpers.js`         | `helpers/src/index.js`                 |

### Task 2.2: Update module names

- [ ] Rename all `Testing.Platform.*` modules to `Replay.*`
- [ ] Update all imports throughout codebase
- [ ] Verify no oz-specific imports remain (except protocol types to be generalized later)

### Task 2.3: Wire up unit test runner

- [ ] Create `test/Main.purs` that runs all `**/Test.purs` modules
- [ ] Add `nix run .#test-unit` derivation
- [ ] Verify all unit tests pass

**Verification**: `nix run .#test-unit` passes with all copied tests

---

## Phase 3: Create Demo Application

The demo app is the **primary testing mechanism**. It's a real application that uses replay, proving the library works for its intended purpose.

### Task 3.1: Create echo-client demo app

A minimal CLI that makes HTTP requests - the simplest possible app that exercises replay.

```
examples/echo-client/
├── src/
│   └── Main.purs       # CLI that calls httpbin.org/anything
├── package.json
└── README.md
```

**Behavior**:

```bash
# Makes POST to httpbin.org/anything with the message
echo-client "hello world"
# Output: {"data": "hello world", "origin": "...", ...}
```

### Task 3.2: Wire demo app to replay

- [ ] Demo app accepts `--platform-url` argument
- [ ] When provided, routes HTTP effects through replay WebSocket
- [ ] When not provided, executes HTTP directly (for comparison)

**Verification**: `nix run .#echo-client -- "test"` works against live httpbin.org

---

## Phase 4: Demo App BDD Features (User-Centric Testing)

These features test what a **user of replay** actually cares about: "Can I use this library to make my tests deterministic?"

### Task 4.1: Live mode feature

```gherkin
Feature: Live mode executes real requests
  As a developer using replay
  I want live mode to execute real HTTP requests
  So that I can verify my app works against real services

  Scenario: Echo client works in live mode
    Given the replay server is running in live mode
    And echo-client is configured to use replay
    When I run echo-client with message "hello from live"
    Then the exit code should be 0
    And the output should contain "hello from live"
    And the output should contain "httpbin.org"
```

### Task 4.2: Record mode feature

```gherkin
Feature: Record mode captures interactions
  As a developer using replay
  I want record mode to capture HTTP interactions to a file
  So that I can replay them later for deterministic tests

  Scenario: Echo client interactions are recorded
    Given the replay server is running in record mode
    And the recording path is "{workspace}/fixtures"
    And echo-client is configured to use replay
    When I run echo-client with message "hello for recording"
    Then the exit code should be 0
    And a recording file should exist at "{workspace}/fixtures/platform-recording.json.zstd"
    And the recording should contain an HTTP request to "httpbin.org"
    And the recording should contain the response with "hello for recording"
```

### Task 4.3: Playback mode feature

```gherkin
Feature: Playback mode returns recorded responses
  As a developer using replay
  I want playback mode to return recorded responses without network
  So that my tests are deterministic and fast

  Scenario: Echo client uses recorded response in playback
    Given I have a recording of echo-client with message "recorded hello"
    And the replay server is running in playback mode with that recording
    And echo-client is configured to use replay
    When I run echo-client with message "recorded hello"
    Then the exit code should be 0
    And the output should match the recorded response exactly
    And no HTTP requests should have been made to httpbin.org

  Scenario: Playback fails clearly for unrecorded request
    Given I have a recording of echo-client with message "recorded hello"
    And the replay server is running in playback mode with that recording
    And echo-client is configured to use replay
    When I run echo-client with message "different message"
    Then the exit code should indicate failure
    And the error should explain no recording matches the request
    And the error should include the request hash for debugging
```

### Task 4.4: Session management feature

```gherkin
Feature: Session isolation for parallel tests
  As a developer running tests in parallel
  I want each test to have an isolated session
  So that recordings don't interfere with each other

  Scenario: Multiple sessions record independently
    Given the replay server is running in record mode
    When I create session "test-a" and run echo-client with "message a"
    And I create session "test-b" and run echo-client with "message b"
    Then session "test-a" recording should contain only "message a"
    And session "test-b" recording should contain only "message b"
```

**Verification**: All demo app BDD features pass in live mode

---

## Phase 5: Generalize Types (Remove oz Dependencies)

### Task 5.1: Make payload types opaque

Replace oz-specific request/response types with generic JSON:

```purescript
-- Before (oz-specific)
data RequestPayload
  = RequestPayloadHttp { method :: String, url :: String, ... }
  | RequestPayloadBaml { functionName :: String, ... }
  | RequestPayloadTextract { ... }

-- After (generic)
type RequestPayload =
  { service :: String      -- "http", "baml", "textract", etc.
  , data :: Json           -- Arbitrary JSON payload
  }
```

### Task 5.2: Make secret keys strings

```purescript
-- Before (oz-specific)
data SecretKey = ApiKey | GcsCredentials | ...

-- After (generic)
type SecretKey = String    -- "api_key", "gcs_credentials", etc.
```

### Task 5.3: Update demo app for generic types

- [ ] Update echo-client to use generic `{ service: "http", data: ... }` format
- [ ] Verify all BDD features still pass

**Verification**: `nix flake check` passes, all tests green

---

## Phase 6: Record Demo App Fixtures & Playback Tests

### Task 6.1: Record fixtures for demo app

```bash
nix run .#test-record-echo-client
git add examples/echo-client/fixtures/
```

### Task 6.2: Verify playback works

```bash
nix run .#test-playback-echo-client   # Should pass without network
nix flake check                        # Playback in sandbox
```

**Verification**: `nix flake check` passes (demo app tests run in playback)

---

## Phase 7: oz Integration

### Task 7.1: Add replay as oz flake input

```nix
# oz/flake.nix
inputs.replay = {
  url = "github:Cambridge-Vision-Technology/replay/issue-438-extract-harness";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.purs-nix.follows = "purs-nix";
};
```

### Task 7.2: Create oz adapter layer

oz needs to convert its specific types to/from replay's generic JSON:

```purescript
-- src/Testing/Platform/Adapter.purs
module Testing.Platform.Adapter where

-- Convert oz RequestPayloadHttp -> generic { service: "http", data: ... }
toReplayRequest :: OzRequestPayload -> Replay.RequestPayload

-- Convert generic response -> oz ResponsePayloadHttp
fromReplayResponse :: Replay.ResponsePayload -> OzResponsePayload
```

### Task 7.3: Update oz to use replay

- [ ] Import replay harness binary from flake
- [ ] Import replay PureScript modules
- [ ] Wire adapter into oz's platform handler
- [ ] Update `features/support/platform_harness_helpers.js` to use `@cvt/replay-helpers`

### Task 7.4: Verify oz tests pass

```bash
cd /Volumes/Git/oz/issue-438-extract-harness
nix run .#test-live -- --name "some scenario"
nix run .#test-record -- --name "some scenario"
nix flake check
```

**Verification**: All oz tests pass with replay as external dependency

---

## Phase 8: oz Cleanup

### Task 8.1: Remove duplicated harness code from oz

- [ ] Remove `src/Testing/Platform/Harness/` directory
- [ ] Remove `harness/` directory
- [ ] Keep only `src/Testing/Platform/Adapter.purs` (oz-specific conversion)
- [ ] Keep oz-specific types in `src/Testing/Platform/Types.purs`

### Task 8.2: Final verification

```bash
nix flake check   # oz
nix flake check   # replay
```

**Verification**: Both repos pass `nix flake check`, no duplicate code

---

## Tasks Summary

| Phase | Task                              | Type        | Status |
| ----- | --------------------------------- | ----------- | ------ |
| 1     | Repository scaffolding            | Infra       | [x]    |
| 2.1   | Copy harness source files         | Migration   | [x]    |
| 2.2   | Update module names               | Migration   | [x]    |
| 2.3   | Wire up unit test runner          | Migration   | [x]    |
| 3.1   | Create echo-client demo app       | Feature     | [ ]    |
| 3.2   | Wire demo app to replay           | Feature     | [ ]    |
| 4.1   | Live mode BDD feature             | Test        | [ ]    |
| 4.2   | Record mode BDD feature           | Test        | [ ]    |
| 4.3   | Playback mode BDD feature         | Test        | [ ]    |
| 4.4   | Session management BDD feature    | Test        | [ ]    |
| 5.1   | Make payload types opaque         | Refactor    | [x]    |
| 5.2   | Make secret keys strings          | Refactor    | [x]    |
| 5.3   | Update demo app for generic types | Refactor    | [ ]    |
| 6.1   | Record demo app fixtures          | Test        | [ ]    |
| 6.2   | Verify playback works             | Test        | [ ]    |
| 7.1   | Add replay as oz flake input      | Integration | [ ]    |
| 7.2   | Create oz adapter layer           | Integration | [ ]    |
| 7.3   | Update oz to use replay           | Integration | [ ]    |
| 7.4   | Verify oz tests pass              | Integration | [ ]    |
| 8.1   | Remove duplicated code from oz    | Cleanup     | [ ]    |
| 8.2   | Final verification                | Cleanup     | [ ]    |

---

## File Structure

```
replay/
├── flake.nix
├── flake.lock
├── agents.yaml
├── CLAUDE.md (generated)
├── README.md
├── package.json
├── package-lock.json
├── .eslintrc.json
├── .envrc
├── .gitignore
├── src/
│   ├── Main.purs                    # Harness CLI entry point
│   ├── Signal.purs
│   ├── Signal.js
│   └── Replay/
│       ├── Server.purs
│       ├── Server.js
│       ├── Handler.purs
│       ├── Session.purs
│       ├── Recorder.purs
│       ├── Player.purs
│       ├── Player/Test.purs
│       ├── Interceptor.purs
│       ├── IdTranslation.purs
│       ├── IdTranslation/Test.purs
│       ├── Types.purs
│       ├── Test.purs
│       ├── Recording.purs
│       ├── Recording/Test.purs
│       ├── Hash.purs
│       ├── Client.purs
│       ├── Client.js
│       ├── Common.purs
│       ├── Normalize.purs
│       ├── Normalize/Test.purs
│       ├── ULID.purs
│       ├── ULID/Test.purs
│       ├── Stream.purs
│       ├── Stream/Test.purs
│       ├── PendingRequests.purs
│       ├── PendingRequests/Test.purs
│       ├── TraceContext.purs
│       ├── TraceContext/Effect.purs
│       ├── TraceContext/Test.purs
│       ├── Time.purs
│       └── Protocol/
│           ├── Types.purs
│           ├── Types/Test.purs
│           └── Envelope.purs
├── test/
│   └── Main.purs                    # Unit test runner
├── helpers/
│   ├── package.json
│   └── src/
│       └── index.js                 # @cvt/replay-helpers
├── examples/
│   └── echo-client/
│       ├── src/
│       │   └── Main.purs
│       ├── package.json
│       └── fixtures/                # Recorded fixtures for playback tests
└── features/
    ├── live_mode.feature
    ├── record_mode.feature
    ├── playback_mode.feature
    ├── session_management.feature
    ├── step_definitions/
    │   └── echo_client_steps.js
    ├── support/
    │   └── world.js
    └── fixtures/
        └── echo-client/
            └── {scenario}/
                └── files/
```

---

## Success Criteria

1. **Demo app validates replay** - echo-client BDD features prove replay works for real applications
2. **Unit tests provide safety net** - All migrated unit tests pass during development
3. **oz integration works** - oz tests pass with replay as external dependency
4. **No duplicate code** - Harness logic lives only in replay after cleanup
5. **Generic types** - Any service type works, not just oz-specific ones
6. **Playback in CI** - `nix flake check` runs demo app tests in playback mode

---

## Workflow Order (CRITICAL)

For each phase with tests:

1. **Live first** → `nix run .#test-live-echo-client` proves logic works
2. **Record** → `nix run .#test-record-echo-client` captures fixtures
3. **Stage** → `git add examples/echo-client/fixtures/`
4. **Playback** → `nix flake check` verifies everything works offline

If playback fails after live passes, it's ALWAYS a packaging/fixture issue, not code.
