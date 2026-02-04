# Plan: Extract Test Harness into Standalone "replay" Repository

**Issue**: Cambridge-Vision-Technology/oz#438
**Branch**: `issue-438-extract-harness`

## Overview

Extract the test harness infrastructure from oz into this standalone repository. The replay library provides WebSocket-based recording/playback for deterministic testing of external effects (HTTP, LLM, cloud APIs).

**Key Design Decisions**:
1. Opaque JSON payloads (service types are strings, payloads are arbitrary JSON)
2. String secret keys (no oz-specific dependencies)
3. Separate JS helpers package (@cvt/replay-helpers)

---

## Phase 1: Repository Scaffolding & Infrastructure

### Task 1.1: Initialize flake.nix with CVT tooling
- [ ] Create flake.nix with inputs: purs-nix, whine, dedup, scythe, drop, agen, eslint-plugin-purescript-ffi, purescript-overlay, treefmt-nix
- [ ] Create package.json with dependencies: ws, ulid, zstd-napi
- [ ] Create agents.yaml for CLAUDE.md generation
- [ ] DevShell with all tools, auto-generates CLAUDE.md on entry
- [ ] treefmt config: purs-tidy, prettier, nixfmt

**Verification**: `nix flake check` passes, `nix develop` works, CLAUDE.md generated

---

## Phase 2: Core Server (Passthrough Mode)

### Task 2.1: Server starts and accepts WebSocket connections

```gherkin
Feature: Replay server connectivity

  Scenario: Server starts on Unix socket
    Given I start replay in passthrough mode on socket "/tmp/replay-test.sock"
    When I connect a WebSocket client to "unix:/tmp/replay-test.sock"
    Then the connection should be established
    And the server should accept messages

  Scenario: Server starts on TCP port
    Given I start replay in passthrough mode on port 19876
    When I connect a WebSocket client to "ws://localhost:19876"
    Then the connection should be established
```

### Task 2.2: Control channel responds to status requests

```gherkin
Feature: Control channel

  Scenario: Get server status
    Given a replay server running in passthrough mode
    When I send a control command "get_status"
    Then I receive a status response with mode "passthrough"
    And the response includes "recordedMessageCount" of 0
```

---

## Phase 3: Session Management

### Task 3.1: Create and close sessions

```gherkin
Feature: Session management

  Scenario: Create a new session
    Given a replay server running in record mode with recording-dir "/tmp/recordings"
    When I send a control command to create session "test-session-1" in record mode
    Then I receive a "session_created" response with sessionId "test-session-1"

  Scenario: Close a session saves recording
    Given a replay server with an active session "test-session-1"
    And the session has recorded 3 messages
    When I send a control command to close session "test-session-1"
    Then I receive a "session_closed" response
    And a recording file exists at "/tmp/recordings/test-session-1/platform-recording.json.zstd"

  Scenario: List active sessions
    Given a replay server with sessions "session-a" and "session-b"
    When I send a control command "list_sessions"
    Then I receive a session list containing "session-a" and "session-b"
```

---

## Phase 4: Recording Mode

### Task 4.1: Record request/response pairs

```gherkin
Feature: Recording mode

  Scenario: Record a simple request/response
    Given a replay server running in record mode
    And a connected client on the program channel
    When I send a command with service "echo" and payload '{"message": "hello"}'
    And the server forwards to platform and receives response '{"message": "hello back"}'
    Then the response is sent back to the client
    And the recording contains 2 messages (request and response)
    And both messages have matching hashes

  Scenario: Recording uses zstd compression
    Given a replay server in record mode with recording-path "/tmp/test.json"
    And the session has recorded messages
    When the server shuts down
    Then the file "/tmp/test.json.zstd" exists
    And the file is valid zstd-compressed JSON
```

---

## Phase 5: Playback Mode

### Task 5.1: Replay recorded responses

```gherkin
Feature: Playback mode

  Scenario: Playback returns recorded response for matching request
    Given a recording file with a request hash "abc123" and response '{"result": "success"}'
    And a replay server running in playback mode with that recording
    When I send a request that hashes to "abc123"
    Then I receive the response '{"result": "success"}'
    And no platform connection is made

  Scenario: Playback fails for unrecorded request
    Given a replay server in playback mode with an empty recording
    When I send a request with service "unknown"
    Then I receive an error response with type "playback_miss"
    And the error message includes the request hash
```

---

## Phase 6: Intercept API

### Task 6.1: Register and match intercepts

```gherkin
Feature: Intercept API

  Scenario: Register an intercept that matches requests
    Given a replay server in passthrough mode
    When I register an intercept matching service "http" with response '{"status": 200}'
    Then I receive an "intercept_registered" response with an interceptId

  Scenario: Intercept returns stubbed response
    Given a replay server with an intercept for service "http" returning '{"mocked": true}'
    When I send a request with service "http"
    Then I receive the response '{"mocked": true}'
    And the intercept match count is 1

  Scenario: Intercept with limited uses
    Given a replay server with an intercept for service "http" with times=1
    When I send 2 requests with service "http"
    Then the first request returns the intercepted response
    And the second request proceeds to platform (or playback)
```

---

## Phase 7: JavaScript Helpers Package

### Task 7.1: Helper functions work with test frameworks

```gherkin
Feature: JavaScript helpers

  Scenario: createSessionForCommand creates a session
    Given a replay server running in record mode
    And a test world object with scenario "my-test-scenario"
    When I call createSessionForCommand(world, "mycommand")
    Then a session is created with ID containing "mycommand-my-test-scenario"
    And world.currentSessionId is set

  Scenario: getSessionPlatformUrl returns correct format
    Given a world with currentSessionId "test-123" and socket "/tmp/replay.sock"
    When I call getSessionPlatformUrl(world)
    Then I receive "unix:/tmp/replay.sock?session=test-123"

  Scenario: checkRecordingExists finds compressed files
    Given a file "/tmp/recording.json.zstd" exists
    When I call checkRecordingExists("/tmp/recording.json")
    Then the result shows exists=true and compressedExists=true
```

---

## Phase 8: Generic Types (No oz dependencies)

### Task 8.1: Opaque JSON payloads work

```gherkin
Feature: Generic payload types

  Scenario: Any JSON payload is accepted
    Given a replay server in record mode
    When I send a request with service "custom" and arbitrary JSON payload
    Then the server records it without validation errors
    And playback returns the exact same payload

  Scenario: Service type is a string
    Given a replay server
    When I send requests with services "foo", "bar-baz", "my_service_v2"
    Then all are accepted as valid service types
```

---

## Tasks Summary

| Phase | Task | Type | Status |
|-------|------|------|--------|
| 1 | Repository scaffolding | Infra | [ ] |
| 2.1 | Server starts/connects | Feature | [ ] |
| 2.2 | Control channel status | Feature | [ ] |
| 3.1 | Session management | Feature | [ ] |
| 4.1 | Recording mode | Feature | [ ] |
| 5.1 | Playback mode | Feature | [ ] |
| 6.1 | Intercept API | Feature | [ ] |
| 7.1 | JS helpers package | Feature | [ ] |
| 8.1 | Generic types | Feature | [ ] |

---

## Files to Create

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
│   ├── Main.purs
│   ├── Signal.purs
│   ├── Signal.js
│   └── Replay/
│       ├── Types.purs
│       ├── Server.purs
│       ├── Server.js
│       ├── Handler.purs
│       ├── Session.purs
│       ├── Recorder.purs
│       ├── Player.purs
│       ├── Interceptor.purs
│       ├── IdTranslation.purs
│       ├── Recording.purs
│       └── Hash.purs
├── helpers/
│   ├── package.json
│   └── src/
│       └── index.js
└── features/
    ├── connectivity.feature
    ├── control.feature
    ├── sessions.feature
    ├── recording.feature
    ├── playback.feature
    ├── intercepts.feature
    ├── helpers.feature
    ├── types.feature
    ├── step_definitions/
    └── support/
```

---

## Source Files to Port from oz

| oz Path | replay Path |
|---------|-------------|
| `src/Testing/Platform/Harness/Server.purs` | `src/Replay/Server.purs` |
| `src/Testing/Platform/Harness/Server.js` | `src/Replay/Server.js` |
| `src/Testing/Platform/Harness/Handler.purs` | `src/Replay/Handler.purs` |
| `src/Testing/Platform/Harness/Session.purs` | `src/Replay/Session.purs` |
| `src/Testing/Platform/Harness/Recorder.purs` | `src/Replay/Recorder.purs` |
| `src/Testing/Platform/Harness/Player.purs` | `src/Replay/Player.purs` |
| `src/Testing/Platform/Harness/Interceptor.purs` | `src/Replay/Interceptor.purs` |
| `src/Testing/Platform/Harness/IdTranslation.purs` | `src/Replay/IdTranslation.purs` |
| `src/Testing/Platform/Harness/Types.purs` | `src/Replay/Harness/Types.purs` |
| `src/Testing/Platform/Recording.purs` | `src/Replay/Recording.purs` |
| `src/Testing/Platform/Hash.purs` | `src/Replay/Hash.purs` |
| `src/Testing/Platform/Types.purs` | `src/Replay/Types.purs` (simplified) |
| `harness/src/Main.purs` | `src/Main.purs` |
| `harness/src/Signal.purs` | `src/Signal.purs` |
| `harness/src/Signal.js` | `src/Signal.js` |
| `features/support/platform_harness_helpers.js` | `helpers/src/index.js` |

---

## Success Criteria

1. **Independence**: replay builds and tests without oz dependency
2. **Protocol Compatibility**: Generic JSON payloads work for any service type
3. **Full Tooling**: All CVT linting/formatting tools configured and passing
4. **CLAUDE.md Generation**: DevShell auto-regenerates CLAUDE.md via agen
5. **BDD Tests**: All feature scenarios pass in playback mode
