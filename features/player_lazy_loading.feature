Feature: Player with lazy loading
  The Player module can work with LazyRecording type to perform playback.
  When a client sends a request matching a recorded hash, the correct response
  is returned and only the matched message is fully decoded.

  Scenario: Playback from lazy-loaded recording
    Given a lazily loaded recording with 50 request-response pairs for playback
    When a client sends a request matching a recorded hash
    Then the correct response should be returned
    And only the matched message should be fully decoded
