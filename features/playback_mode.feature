Feature: Playback mode returns recorded responses
  The replay harness in playback mode can load recording fixtures
  and return previously recorded responses.

  Scenario: Harness starts in playback mode
    Given I have a recording fixture
    And the replay server is running in playback mode
    Then the harness should be accepting connections
