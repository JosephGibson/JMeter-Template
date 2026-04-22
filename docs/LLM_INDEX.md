# LLM_INDEX

File map for LLM navigation. Use this before exploring; do not re-derive structure with `find`/`ls`.

## Root

| Path | Purpose |
|---|---|
| [jmeter-template-plan.md](../jmeter-template-plan.md) | Authoritative spec: goal, stack, requirements, schemas, phases, decisions |
| [README.md](../README.md) | Quick orientation, run command, status |
| [AGENTS.md](../AGENTS.md) | LLM operating rules and hard constraints |
| [CHANGELOG.md](../CHANGELOG.md) | Release history (Keep a Changelog) |
| [.gitignore](../.gitignore) | Excludes `results/`, `*.jtl`, logs, IDE noise |
| [.claudeignore](../.claudeignore) | Excludes run artifacts from LLM context |

## Plan section index

| § | Topic |
|---|---|
| 1 | Goal |
| 2 | Tech stack |
| 3 | Hard constraints |
| 4.1 | Load shaping (closed-user model, derived values) |
| 4.2 | Scenario orchestration (Weighted Switch + Module Controllers) |
| 4.3 | CSV data handling |
| 4.4 | Results collection (`runDir`, zip) |
| 4.5 | `Test_executor.bat` arg surface |
| 4.6 | Logging module (`props["log"]`) |
| 4.7 | `.jmx` root-level defaults |
| 4.8 | Pacing mechanism (4 elements) |
| 4.9 | Proxy support |
| 4.10 | Test Fragments |
| 4.11 | Assertion requirement |
| 5 | Project folder structure |
| 6.1 | `environmentVariables.json` schema |
| 6.2 | Profile JSON schema |
| 6.3 | `-J` property reference |
| 7 | Runtime contracts (banner, log lines, fatal errors, results guarantees) |
| 8 | Implementation phases (1–8, sequential, with acceptance checks) |
| 9 | Decisions log (1–18) |
| 10 | Open questions |
| 11 | References (JMeter docs, plugins, tooling) |

## Future paths (not yet present)

Per plan §5, the implemented template will live at `./{projectName}/` with:

- `jmeter.jmx` — root test plan
- `Test_executor.bat` — launcher
- `environmentVariables.json` — env definitions
- `data/Sc{NN}_{Purpose}.csv` — per-scenario CSV inputs
- `profiles/{Load,Soak,Smoke,Stress,Breakpoint,debug}.json` — load profiles
- `results/` — per-run output (gitignored)
