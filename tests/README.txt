Run with the official Luau CLI:
  luau gameplay_tests.luau
  luau freecam_tests.luau

Regenerate from current src/ first after editing:
  python tests/build_tests.py
  python tests/build_freecam_tests.py

The gameplay output uses cumulative totals, not separate assertion counts.
These harnesses mock Roblox services and do not replace Studio integration tests.
cases/*.luau.in are insertion templates, not standalone executable scripts.
