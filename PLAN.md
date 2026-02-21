# Issue #18: SDK Foundation — Protocol Types & Platform FFI

## Overview

Foundation layer for the cross-platform harness SDK. Pure data types + thin FFI stubs.
No routing logic — just the building blocks that compile on both JS and Erlang backends.

Closes #18. Blocks #19.

## Risks

1. **simple-json availability**: May not be in purs-nix registry. Fallback: use Argonaut
   initially (proven, available), add simple-json when Erlang backend lands.
2. **Erlang build**: This repo is JS-only. `.erl` stubs created but not compiled/tested
   until #21 (blackbriar migration).

## Tasks

### Task 1: Json.Nullable — Maybe-based internals

- [ ] Refactor `JsonNullable` to use `Maybe` internally instead of `Data.Nullable.Nullable`
- [ ] Same JSON encoding: `Nothing` → JSON `null` (not field omission)
- [ ] Remove `nullable` from purs-nix dependencies if no longer needed elsewhere
- **Verify**: existing playback tests pass (regression), add unit test for null encoding
- **Files**: `src/Json/Nullable.purs`

### Task 2: SDK project structure & Nix build

- [ ] Create `sdk/src/Replay/SDK/` directory layout
- [ ] Add SDK PureScript compilation target to `flake.nix`
- [ ] Add SDK unit test runner (`nix run .#test-sdk-unit`)
- **Verify**: `nix build .#sdkTest` compiles
- **Files**: `sdk/`, `flake.nix`

### Task 3: Observability ADT

- [ ] `data Observability a = Internal a | Observable a` with helpers
- [ ] Pure data type, no FFI
- **Verify**: compiles, unit test for tag inspection
- **Files**: `sdk/src/Replay/SDK/Observability.purs`

### Task 4: Protocol types

- [ ] `Replay.SDK.Protocol` — Envelope, Command, Event, RequestPayload, ResponsePayload, Channel, StreamId, TraceId, etc.
- [ ] JSON encode/decode instances (Argonaut initially, same wire format as server)
- **Verify**: unit test — serialize known messages, compare JSON output byte-for-byte with existing server types. Round-trip decode.
- **Files**: `sdk/src/Replay/SDK/Protocol.purs`

### Task 5: Envelope builders

- [ ] `Replay.SDK.Envelope` — `buildRequestEnvelope`, `buildResponseEnvelope`
- [ ] Absorb from existing `Replay.Protocol.Envelope`
- **Verify**: unit test — constructed envelopes have correct structure
- **Files**: `sdk/src/Replay/SDK/Envelope.purs`

### Task 6: Hash FFI (JS)

- [ ] `Replay.SDK.Hash` — SHA-256 + canonical JSON
- [ ] JS FFI using `crypto` + `json-stable-stringify` (extract from `FFI.Crypto`)
- **Verify**: unit test — hash known payloads, compare to expected values from existing recordings
- **Files**: `sdk/src/Replay/SDK/Hash.purs`, `sdk/src/Replay/SDK/Hash.js`

### Task 7: ULID FFI (JS)

- [ ] `Replay.SDK.ULID` — generate, parse, validate
- [ ] JS FFI using `ulid` npm (extract from `Replay.ULID`)
- **Verify**: unit test — generated ULIDs match Crockford Base32 format, parse round-trips
- **Files**: `sdk/src/Replay/SDK/ULID.purs`, `sdk/src/Replay/SDK/ULID.js`

### Task 8: Transport FFI (JS)

- [ ] `Replay.SDK.Transport` — connect, send, receive, disconnect
- [ ] JS FFI using `ws` npm. Returns `Effect`, not `Aff`
- **Verify**: BDD — connect to harness, send envelope, receive response
- **Files**: `sdk/src/Replay/SDK/Transport.purs`, `sdk/src/Replay/SDK/Transport.js`

### Task 9: Erlang FFI stubs

- [ ] `.erl` files for Hash, ULID, Transport (structure only)
- [ ] Not compiled/tested in this repo — deferred to #21
- **Verify**: files exist, reasonable structure
- **Files**: `sdk/src/Replay/SDK/Hash.erl`, `sdk/src/Replay/SDK/ULID.erl`, `sdk/src/Replay/SDK/Transport.erl`

## BDD Features

```gherkin
Feature: SDK wire format compatibility
  The SDK protocol types and transport layer produce valid
  wire format that the replay harness server accepts.

  Scenario: SDK-format envelope is accepted by harness
    Given the replay server is running in passthrough mode
    And I am connected via WebSocket
    When I send an SDK-format command envelope with service "test" and payload '{"msg":"hello"}'
    Then the harness should return the command on the platform channel
    And the platform channel payload service should be "test"

  Scenario: SDK-format control command works
    Given the replay server is running in passthrough mode
    And I am connected via WebSocket
    When I send a GetStatus control command
    Then the response should contain mode "passthrough"
```

## Files Created

| Path | Purpose |
|---|---|
| `sdk/src/Replay/SDK/Protocol.purs` | Protocol types with JSON instances |
| `sdk/src/Replay/SDK/Envelope.purs` | Envelope builders |
| `sdk/src/Replay/SDK/Observability.purs` | Internal / Observable ADT |
| `sdk/src/Replay/SDK/Hash.purs` + `.js` + `.erl` | Canonical hash |
| `sdk/src/Replay/SDK/ULID.purs` + `.js` + `.erl` | ID generation |
| `sdk/src/Replay/SDK/Transport.purs` + `.js` + `.erl` | WebSocket transport |
| `sdk/test/Main.purs` | SDK unit test runner |
| `features/sdk_wire_format.feature` | BDD wire format tests |
| `features/step_definitions/sdk_wire_format_steps.js` | Step implementations |

## Files Modified

| Path | Change |
|---|---|
| `src/Json/Nullable.purs` | Maybe-based internals, drop `Data.Nullable` |
| `flake.nix` | SDK compilation target, test runner, deps |

## Execution Order (TDD)

1. Write failing BDD features + unit test stubs
2. Task 1 (Json.Nullable) — run existing tests to verify regression
3. Task 2 (project structure + Nix) — get SDK compiling
4. Tasks 3–7 (SDK modules) — implement one at a time, unit tests go green
5. Task 8 (Transport) — BDD tests go green
6. Task 9 (Erlang stubs) — last, no tests
7. `nix flake check` — all green
