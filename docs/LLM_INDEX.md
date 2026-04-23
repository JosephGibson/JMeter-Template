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
| 4.2 | Scenario orchestration (per-scenario Throughput Controllers + Module Controllers) |
| 4.3 | CSV data handling |
| 4.4 | Results collection (`runDir`, archiving policy) |
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
| 9 | Decisions log (1–23) |
| 10 | Open questions |
| 11 | References (JMeter docs, tooling) |

## Template implementation

Reference implementation under [../template/](../template/):

| Path | Purpose |
|---|---|
| [../template/jmeter.jmx](../template/jmeter.jmx) | Root test plan (TestPlan, HTTP Defaults/Header/Cache/Cookie Managers, UDV, Assertion Failure Listener, setUp + Main (stock Thread Group) + tearDown thread groups, Fragments subtree with short Sc01/Sc02 scaffolds) |
| [../template/Test_executor.bat](../template/Test_executor.bat) | CLI launcher — arg parsing, runDir creation, JMeter invocation |
| [../template/environmentVariables.json](../template/environmentVariables.json) | Server definitions for `dev` / `staging` / `prod` |
| [../template/profiles/](../template/profiles/) | Six profile JSON files (Load, Soak, Smoke, Stress, Breakpoint, debug) |
| [../template/data/Sc01_SomeData.csv](../template/data/Sc01_SomeData.csv) | Example CSV input (sharing=All threads, recycle=true, stopThread=false) |
| `../template/results/` | Per-run runDir (gitignored) |

### .jmx component map

| Component | Role (plan ref) |
|---|---|
| HTTP Request Defaults | Scheme/host/port bound to `${__P(scheme)}` / `${__P(host)}` / `${__P(port)}`; proxy bound to `${__P(proxy.host,)}` / `${__P(proxy.port,)}` (§4.7, §4.9) |
| setUp → SU01 | Config loader + banner + logging module install, including profile/`-Jlog.*` logging overrides (§4.1, §4.6, §7.1) |
| Main Thread Group (stock) | `num_threads=${__P(concurrentUsers,1)}`, `ramp_time=${__P(rampUpSeconds,60)}`, scheduler on, `duration=${__P(durationSeconds,3720)}` (= rampUpSeconds + holdSeconds + rampDownSeconds) (§4.1) |
| Per-scenario Throughput Controllers | One sibling TC per scenario, Percent Executions mode, `percentThroughput=${__P(Sc{NN}.weight)}` (§4.2) |
| Module Controllers | One inside each Throughput Controller, pointing at the matching `Sc{NN}` Transaction Controller in Fragments (§4.2) |
| Fragments → Sc01/Sc02 | Scaffold Transaction Controllers (generate-parent=true, include-timers=true) with pacing pattern (§4.8) |
| Fragments → Log to File | Disabled JSR223 PostProcessor writing to `${runDir}/custom/{scenario}.log` (§4.10) |
| Fragments → Proxy-aware HTTP Request | Example sampler overriding proxy (§4.10) |
| Fragments → Assertion Patterns | Status-only / body-contains / JSON-path examples (§4.10, §4.11) |
| Fragments → CSV Data Set | Disabled template for per-scenario CSVs (§4.3) |
| tearDown → TD01 | Closes shared writers, emits summary (§4.4) |
| LN01 Assertion Failure Summary | JSR223 Listener at TestPlan root; emits error line on any failed assertion (§4.6) |

## Execution docs

| Path | Purpose |
|---|---|
| [Usage.md](Usage.md) | Template concept, profile schema, pacing math, HAR-to-JMX workflow, CSV conventions, proxy, logging API |
| [Execution.md](Execution.md) | Dev flow (Record/Build/Debug/Execute), GUI vs CLI behavior, launcher arg reference, results folder contents, pacing breach interpretation, exit codes |
