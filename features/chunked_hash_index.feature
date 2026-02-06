Feature: Non-blocking hash index building
  The hash index builder processes messages in chunks with event loop yields
  between chunks, ensuring the Node.js event loop remains responsive during
  index construction. This prevents timeout issues when building indexes for
  large recordings with many messages.

  Scenario: Build index while remaining responsive
    Given a recording with 1000 messages
    When building the hash index
    And sending heartbeat messages every 50ms
    Then all heartbeats should receive responses within 100ms
