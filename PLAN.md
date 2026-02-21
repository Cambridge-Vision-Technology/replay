# Issue #14: SDK auto-stamps envelope timestamps

Closes #14

## Problem

The `buildRequestEnvelope` and `buildResponseEnvelope` functions in
`Replay.Protocol.Envelope` require callers to pass a `timestamp :: String`
parameter. This forces application transport code to call the system clock
directly just to build an envelope, leaking an `Effect` into plumbing that
should be simpler.

## Analysis

The issue proposes moving timestamp stamping from clients to the harness server.
However, the harness is a pure message broker — it already has `recordedAt` for
observation time. Stamping `timestamp` in the harness would create redundancy,
break bypass-mode consistency, and change the semantics of the field.

The correct fix is in the **client SDK**: make the envelope builders auto-stamp
timestamps internally, so callers never need direct clock access.

## Tasks

### Task 1: Write BDD feature (RED)

- [ ] `features/sdk_timestamp_stamping.feature` — scenarios verifying that
      envelopes sent through the SDK have valid ISO 8601 timestamps
- [ ] `features/step_definitions/sdk_timestamp_steps.js` — step implementations
      using the harness's `get_messages` control command to inspect timestamps
- [ ] Run tests to confirm they fail (feature not yet implemented)

### Task 2: Make envelope builders effectful + auto-stamp

- [ ] `src/Replay/Protocol/Envelope.purs`:
  - Remove `timestamp :: String` parameter from `buildRequestEnvelope`
  - Call `Replay.Time.getCurrentTimestamp` internally
  - Return `Effect (Envelope Command)` instead of pure `Envelope Command`
  - Same treatment for `buildResponseEnvelope`

### Task 3: Update Handler call sites

- [ ] `src/Replay/Handler.purs`:
  - Update `handleInterceptMatch` (line ~148-150): remove manual
    `getCurrentTimestamp`, use effectful `buildResponseEnvelope`
  - Update `handleProgramRecord` CommandClose branch (line ~274): same
  - Update `handlePlatformPassthrough` CommandClose branch (line ~233): same

### Task 4: Update echo-client

- [ ] `examples/echo-client/src/Main.purs`:
  - Remove manual `getCurrentTimestamp` call
  - Use effectful `buildRequestEnvelope` (no timestamp param)

### Task 5: Re-record fixtures and verify

- [ ] `nix run .#format-fix`
- [ ] `nix run .#test-record` — re-record fixtures
- [ ] `git add features/fixtures/`
- [ ] `nix flake check` — verify playback passes
