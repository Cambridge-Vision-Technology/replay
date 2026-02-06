Feature: Parallel playback sessions with large recordings
  The lazy loading solution resolves the original issue where parallel sessions
  with large recordings caused timeout errors. This test verifies that multiple
  concurrent playback sessions can operate on large recordings without blocking
  the event loop or experiencing timeout errors.

  Scenario: Multiple concurrent sessions with 100MB recordings
    Given 4 separate recording files of approximately 25MB each
    When 4 playback sessions are started simultaneously
    And each session makes 10 requests within 5 seconds
    Then all sessions should complete without timeout errors
    And all responses should be correct
