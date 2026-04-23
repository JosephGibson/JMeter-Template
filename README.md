# JMeter Template

Reusable JMeter test plan for API and webflow load tests. Profile-driven config, `.bat` launcher, timestamped per-run results folder.

## Stack

- JMeter 5.6.3, Java 17 LTS
- Plugins: Ultimate Thread Group, Weighted Switch Controller
- Scripting: Groovy (JSR223)
- Launcher: Windows `.bat` (no PowerShell)
- OS target: Windows 10+

## Layout

```
{projectName}/
  jmeter.jmx
  Test_executor.bat
  environmentVariables.json
  data/         Sc{NN}_{Purpose}.csv
  profiles/     {Load,Soak,Smoke,Stress,Breakpoint,debug}.json
  results/      {projectName}_{yyyyMMdd_HHmmss}/
```

## Run

```
Test_executor.bat --profile <name> --env <name> --project <name>
                  [--mode weighted|sequential]
                  [--proxy-host <host> --proxy-port <port>]
                  [--results-root <path>]
```

GUI defaults when `-J` unset: `profile=debug`, `env=dev`, `projectName=debug`.

## Status

Phases 1–8 implemented under [template/](template/). Pending: in-JMeter validation against each phase's acceptance checks (plan §8) — the template was authored on Linux and has not yet been opened in a Windows JMeter GUI.

Implementation notes:

- Module Controller node paths are written as `(displayName, className)` pairs; JMeter may re-link on first GUI save. Verify each Module Controller's target in the GUI before the first CLI run.
- Every `.jmx` JSR223 block has an HTML header comment stating purpose, props/vars read, and values written.
- Sc01/Sc02 are short scaffolds for template mechanics; adapted project scenarios should expand or replace them with 15–25 meaningful HTTP calls.

## Docs

- [jmeter-template-plan.md](jmeter-template-plan.md) — full design spec, file schemas, phased deliverables, decisions log
- [docs/Usage.md](docs/Usage.md) — template concept, profile schema, pacing math, HAR cleanup, CSV conventions, proxy, logging
- [docs/Execution.md](docs/Execution.md) — Record/Build/Debug/Execute flow, launcher arg reference, results folder, pacing-breach interpretation, exit codes
- [AGENTS.md](AGENTS.md) — LLM operating rules for this repo
- [docs/LLM_INDEX.md](docs/LLM_INDEX.md) — file map for LLM navigation
- [CHANGELOG.md](CHANGELOG.md) — release history
