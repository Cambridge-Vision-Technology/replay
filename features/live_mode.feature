Feature: Live mode executes real requests
  The echo-client can make direct HTTP requests without going through
  the replay harness.

  Scenario: Echo client works in live mode
    When I run echo-client directly with message "hello from live"
    Then the exit code should be 0
    And the output should contain "hello from live"
