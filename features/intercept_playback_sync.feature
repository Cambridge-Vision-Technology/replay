Feature: Intercept and playback coexistence
  When intercepts are active during playback mode, intercepted requests should
  return the intercept response AND the corresponding recording entry should be
  consumed so that subsequent non-intercepted requests still find the correct
  recorded response. The player's hash index must stay in sync.

  Scenario: Single intercepted request during playback
    Given I record a session with an HTTP request to "https://api.example.com/users"
    And I restart the harness in playback mode
    And I register an intercept for service "http" matching url "https://api.example.com/users"
    When I replay the same HTTP request to "https://api.example.com/users"
    Then the response should come from the intercept
    And the harness should still be operational

  Scenario: Mixed intercepted and non-intercepted requests during playback
    Given I record a session with 3 identical requests to "https://api.example.com/users"
    And I restart the harness in playback mode
    And I register an intercept for service "http" matching url "/users" with times 1
    When I replay 3 identical requests to "https://api.example.com/users"
    Then the first response should come from the intercept
    And the remaining 2 responses should come from the recording
    And the harness should still be operational

  Scenario: Multiple identical-hash intercepted requests during playback
    Given I record a session with 4 identical requests to "https://api.example.com/data"
    And I restart the harness in playback mode
    And I register an intercept for service "http" matching url "https://api.example.com/data" with times 3
    When I replay 4 identical requests to "https://api.example.com/data"
    Then the first 3 responses should come from the intercept
    And the last response should come from the recording
    And the harness should still be operational
