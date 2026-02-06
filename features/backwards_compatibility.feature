Feature: Backwards compatibility
  The new lazy loading implementation must work with existing recording files
  created by the previous version. All existing recordings should load correctly
  with the lazy loader and playback should work identically to before.

  Scenario: Existing recordings work with lazy loader
    Given a recording created with the previous version
    When loaded with the new lazy loader
    Then playback should work identically to before
    And all message hashes should be accessible
