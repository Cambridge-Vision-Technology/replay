Feature: Record mode captures interactions
  The replay harness in record mode starts successfully and is ready
  to capture request/response interactions.

  Scenario: Harness starts in record mode
    Given the replay server is running in record mode
    Then the harness should be accepting connections
