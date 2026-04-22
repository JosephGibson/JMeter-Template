# JMeter Template

Reusable JMeter test plan for API and webflow load tests. Profile-driven config, `.bat` launcher, timestamped result archives.

## Stack

- JMeter 5.6.3, Java 17 LTS
- Plugins: Ultimate Thread Group, Weighted Switch Controller
- Scripting: Groovy (JSR223)
- Launcher: Windows `.bat` (no PowerShell)
- OS target: Windows 10+ (uses bundled `tar.exe`)

## Layout

```
{projectName}/
  jmeter.jmx
  Test_executor.bat
  environmentVariables.json
  data/         Sc{NN}_{Purpose}.csv
  profiles/     {Load,Soak,Smoke,Stress,Breakpoint,debug}.json
  results/      {projectName}_{yyyyMMdd_HHmmss}/  + .zip sibling
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

Pre-implementation. See [jmeter-template-plan.md](jmeter-template-plan.md) for full spec; phases 1–8 not yet started.

## Docs

- [jmeter-template-plan.md](jmeter-template-plan.md) — full design spec, file schemas, phased deliverables, decisions log
- [AGENTS.md](AGENTS.md) — LLM operating rules for this repo
- [docs/LLM_INDEX.md](docs/LLM_INDEX.md) — file map for LLM navigation
- [CHANGELOG.md](CHANGELOG.md) — release history
