# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project plan ([jmeter-template-plan.md](jmeter-template-plan.md)) covering goal, stack, constraints, functional requirements, file schemas, runtime contracts, and 8 phased deliverables.
- Baseline LLM-optimized documentation: README, AGENTS, LLM_INDEX, ignore files.
- Template implementation under [template/](template/) covering plan phases 1–7:
  - [template/jmeter.jmx](template/jmeter.jmx) — root-level HTTP defaults/header/cache/cookie managers; setUp with config loader + banner + thread-safe logging module; Ultimate Thread Group sized from derived `concurrentUsers`; Weighted Switch Controller with Module Controllers for Sc01/Sc02; Fragments subtree containing Sc01/Sc02 Transaction Controllers (with 3-step pacing PreProcessor + PostProcessor + Flow Control Action Pause(0) + Constant Timer), plus disabled Log-to-File, Proxy-aware HTTP Request, Assertion Patterns, and CSV Data Set fragments; tearDown Thread Group finalizes writers; top-level JSR223 Assertion Failure Listener.
  - [template/Test_executor.bat](template/Test_executor.bat) — arg parser, `runDir` creation, JMeter invocation with `-l/-j/-e/-o`, post-success zip via `tar.exe -a -cf`.
  - [template/environmentVariables.json](template/environmentVariables.json) — dev / staging / prod.
  - [template/profiles/](template/profiles/) — Load, Soak, Smoke, Stress, Breakpoint, debug (plan §6.2 schema).
  - [template/data/Sc01_SomeData.csv](template/data/Sc01_SomeData.csv) — example CSV input.
- Phase 8 documentation: [docs/Usage.md](docs/Usage.md) (template concept, profile schema, pacing math, HAR cleanup, CSV conventions, proxy, logging) and [docs/Execution.md](docs/Execution.md) (dev flow, GUI vs CLI, arg reference, results folder, pacing breach interpretation, exit codes).
