Feature: On-demand message decoding
  Messages in a lazily loaded recording are stored as raw JSON and decoded
  only when accessed via hash lookup. This minimizes memory usage and ensures
  that only the messages actually needed are processed.

  Scenario: Messages decoded only when needed
    Given a lazily loaded recording with 90 messages
    When I request playback of a specific hash
    Then only the matching message should be decoded
    And memory usage should be proportional to decoded messages only
