# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project plan ([jmeter-template-plan.md](jmeter-template-plan.md)) covering goal, stack, constraints, functional requirements, file schemas, runtime contracts, and 8 phased deliverables.
- Baseline LLM-optimized documentation: README, AGENTS, LLM_INDEX, ignore files.
- Template implementation under [template/](template/) covering plan phases 1–7:
  - [template/jmeter.jmx](template/jmeter.jmx) — root-level HTTP defaults/header/cache/cookie managers; setUp with config loader + banner + thread-safe logging module; stock Thread Group sized from derived `concurrentUsers`; per-scenario Throughput Controllers with Module Controllers for Sc01/Sc02; Fragments subtree containing Sc01/Sc02 Transaction Controllers (with 3-step pacing PreProcessor + PostProcessor + Flow Control Action Pause(0) + Constant Timer), plus disabled Log-to-File, Proxy-aware HTTP Request, Assertion Patterns, and CSV Data Set fragments; tearDown Thread Group finalizes writers; top-level JSR223 Assertion Failure Listener.
  - [template/Test_executor.bat](template/Test_executor.bat) — arg parser, `runDir` creation, JMeter invocation with `-l/-j/-e/-o`, and exit-code propagation.
  - [template/environmentVariables.json](template/environmentVariables.json) — dev / staging / prod.
  - [template/profiles/](template/profiles/) — Load, Soak, Smoke, Stress, Breakpoint, debug (plan §6.2 schema).
  - [template/data/Sc01_SomeData.csv](template/data/Sc01_SomeData.csv) — example CSV input.
- Phase 8 documentation: [docs/Usage.md](docs/Usage.md) (template concept, profile schema, pacing math, HAR cleanup, CSV conventions, proxy, logging) and [docs/Execution.md](docs/Execution.md) (dev flow, GUI vs CLI, arg reference, results folder, pacing breach interpretation, exit codes).

### Fixed
- Hardened [template/Test_executor.bat](template/Test_executor.bat) for paths containing spaces by quoting mandatory `-J` arguments and removing the single unquoted `JFLAGS` blob.
- Replaced the launcher's hard dependency on deprecated `wmic` timestamps with a Java 17 timestamp helper plus `wmic` / `%DATE%` fallback paths, without adding PowerShell.
- Wired profile logging settings and `-Jlog.level` / `-Jlog.colors` overrides into the JMeter logging module, and preserved scenario/step context in `jmeter.log`.
- Changed scenario Transaction Controller parent samples to include timers so scenario timings reflect the full paced session duration.
- Added a status assertion to the disabled proxy-aware HTTP sampler example so copied HTTP sampler fragments preserve the assertion rule.
- Clarified documentation that committed Sc01/Sc02 flows are short scaffolds and adapted project scenarios should expand or replace them with 15–25 meaningful HTTP calls.
- Fixed Think Time scope in both `Sc01` and `Sc02` Transaction Controllers: each Think Timer is now a child of the sampler it should delay (step 2 and step 3), not a TC-level sibling. At TC level, every timer runs before every sibling sampler, so the prior topology multiplied the intended delay by the sampler count and caused unavoidable pacing breaches on every iteration.
- Narrowed the TestPlan-root `LN01 Assertion Failure Summary` listener to early-return when `CURRENT_SCENARIO` is unset, so setUp/tearDown samples skip the full inspection path.
- `SU01 Load Config + Banner` now closes and removes any stale `writer.*` entries left in `props` when a prior GUI run stopped before `TD01 Finalize` ran, so the next GUI run starts with a fresh per-scenario writer.
- Sc01/Sc02 iter-start PreProcessors now seed `vars["DELAY_TIME"]="0"` alongside `iterStart` and `CURRENT_SCENARIO`, so the Pacing Timer never reads a literal `${DELAY_TIME}` if the PostProcessor is skipped.
- Bound the root `HTTP Header Manager`'s `User-Agent` to `JMeter-Template/${TEMPLATE_VERSION}` so the header stays consistent with the `TEMPLATE_VERSION` User Defined Variable.
- Corrected stock Thread Group scheduler duration derivation to `rampUpSeconds + holdSeconds + rampDownSeconds`, matching JMeter's total Duration semantics and preserving the configured at-capacity tail window for long-ramp profiles.
- `Test_executor.bat` now rejects partial proxy configuration: `--proxy-host` and `--proxy-port` must be supplied together.
- Shortened the bundled `Smoke` and `debug` profile pacing from 600s to 30s; `Smoke` now has enough scheduler duration to complete scaffold flows, and `debug` is a long-running GUI profile intended for manual stop.

### Changed
- Dropped all JMeter plugin dependencies so the template runs on stock JMeter 5.6.3 only (driver: users cannot reliably get plugin installs approved in locked-down environments). Ultimate Thread Group replaced by stock Thread Group with scheduler enabled (`duration = rampUpSeconds + holdSeconds + rampDownSeconds`); `rampDownSeconds` now applies as an at-capacity tail window before a hard stop rather than a gradual ramp-down. BlazeMeter Weighted Switch Controller replaced by one stock Throughput Controller per scenario (Percent Executions mode); scenario weights are now percentages (set them to sum to 100). `mode=sequential` becomes probabilistic equal-share (`100/N` per scenario) — the deterministic round-robin that the plugin provided does not survive the switch. Plan §2/§4.1/§4.2/§4.7/§6.2/§7.1/§8 Phase 4/§9 (Decisions #2, #11, new #23)/§10/§11, README, `docs/Usage.md`, `docs/Execution.md`, and `docs/LLM_INDEX.md` are aligned. SU01 publishes a new `durationSeconds` prop consumed by the Thread Group; banner relabelled `Ramp / Hold / Tail`.
- Removed the launcher's `tar.exe` zip step and the accompanying `<run>.zip` sibling output. The host environment doesn't permit `tar.exe`, and the only in-JMeter zip hook (`TD01`) runs before JMeter emits the HTML dashboard, so it can't archive a complete `runDir/`. Plan §4.4 / §4.5 / §7.4, Decision #17, docs, and `--help` output are aligned; users zip `runDir/` manually when shipping results.
- Dropped the unused `-JresultsRootDir` pass-through from the launcher's JMeter invocation; `-JrunDir` is what the test plan actually reads.
- Scoped the "every sampler must have an assertion" rule in AGENTS.md and plan §4.11 to the Main Thread Group. `SU01`/`TD01` JSR223 samplers set their own `SampleResult.successful` from script and are exempt.
- Clarified inline comments on the `Fragment: Assertion Patterns` controller (reference palette only; enabling the controller itself with no sampler in scope guarantees a failure), and on the CSV Data Set fragment (path relative to the `.jmx` directory).
