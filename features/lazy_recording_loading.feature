Feature: Lazy recording loading
  The lazy recording loader can load large recording files without blocking
  the Node.js event loop. It parses only metadata upfront and stores raw JSON
  for messages to be decoded on-demand.

  Scenario: Load large recording without event loop blocking
    Given a compressed recording file with 90 messages totaling 100MB
    When I start loading the recording
    And simultaneously send 10 heartbeat messages at 100ms intervals
    Then all heartbeat responses should arrive within 200ms of sending
    And the recording metadata should be available
