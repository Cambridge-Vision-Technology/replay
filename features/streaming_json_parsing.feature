Feature: Streaming JSON parsing
  The streaming JSON parser can parse large JSON files without blocking
  the Node.js event loop, allowing other operations to continue.

  Scenario: Parse large JSON without blocking
    Given a 50MB JSON file containing an array of 1000 objects
    When I parse the file using the streaming parser
    Then the event loop should remain responsive (heartbeat messages continue)
    And all objects should be parsed correctly
