# Property Test Quick Start

Property tests are expensive (60-120s each). They are tagged `:skip` so they do not run by default. Include `:skip` explicitly when you want them.

## Common commands

- Fast unit tests (default CI):  
  `mix test --exclude property`

- Full property suite (slow):  
  `mix test --include skip --only property --timeout 120000`

- Coverage-only property check (slow):  
  `mix test --include skip --only property_coverage --timeout 120000`

- Coverage frequency sanity check (slow):  
  `mix test --include skip --only property_coverage_frequency --timeout 120000`

- Integration (no synthetic tokens) check (slow):  
  `mix test --include skip --only property_integration --timeout 120000`

- Error-tolerance properties (slow):  
  `mix test --include skip --only property_error --timeout 120000`

## Tips

- Run locally before larger changes; expect several minutes for the full suite.
- Use longer timeouts (`--timeout 120000` or higher) to avoid ExUnit aborts.
- Keep generators as-is for fidelity; add a future `:property_smoke` tag if faster feedback is needed.
