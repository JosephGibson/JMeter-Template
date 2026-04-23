# JMeter Template — Project Plan

## 1. Goal

Reusable JMeter template for API and webflow load tests. Configured via profile files, executed via a thin `.bat` launcher, results auto-collected into a timestamped run directory.

## 2. Tech Stack

| Component | Choice |
|---|---|
| OS | Windows 10+ (Windows Terminal recommended for ANSI output) |
| JMeter | 5.6.3 baseline (re-validate the template when upgrading) |
| Java | 17 LTS JDK (recommended baseline; includes `keytool` for HTTPS recording) |
| Scripting | Groovy (JSR223) |
| Launcher | `.bat` (thin orchestration: args, run-dir creation, JMeter invocation) |
| Required plugins | None (stock JMeter 5.6.3 only) |

## 3. Constraints

- One `.jmx` per project; copy-and-modify is the reuse pattern.
- No code duplication across scenarios.
- Scenario ID format: `Sc01`, `Sc02`, ... (zero-padded, two digits).
- Adapted project scenarios should contain 15–25 meaningful HTTP calls. The committed Sc01/Sc02 flows are short scaffolds that demonstrate the template mechanics and are expanded or replaced during project build-out.
- Dev flow: Record → Build in GUI → Debug in GUI → Execute in CLI.
- Template root: `./{projectName}/` (all paths in this plan are relative to that root unless marked otherwise).
- HAR is the primary recording input.
- No PowerShell.

## 4. Functional Requirements

### 4.1 Load Shaping

- Default model: **closed-user model**. Each JMeter thread loops over the scenario selectors. With scenario percentages summing to 100, the expected rate is one paced scenario execution per thread loop, but stock Throughput Controllers make independent decisions, so an individual loop can execute 0, 1, or multiple scenarios.
- Tester inputs only: `sessionDurationSeconds`, `targetSessionsPerHour`.
- Derived at runtime:
  - `concurrentUsers = max(1, ceil(targetSessionsPerHour * sessionDurationSeconds / 3600))`
  - `pacingSeconds = sessionDurationSeconds`
  - `thinkTimeBudgetSeconds = max(sessionDurationSeconds − estimatedIterationSeconds, 0)`
- Ramp-up / hold via stock Thread Group (scheduler enabled) using the derived `concurrentUsers`. Ramp-up = `rampUpSeconds`; scheduler duration = `rampUpSeconds + holdSeconds + rampDownSeconds` because JMeter's stock Thread Group duration is total thread-group lifetime after startup delay.
- `rampDownSeconds` is applied as an additional at-capacity **tail window** after ramp-up and hold, before the scheduler hard-stops all threads. Stock Thread Group has no gradual ramp-down; keeping the field preserves existing profile schemas and gives an at-capacity buffer for in-flight iterations, but threads end abruptly when the scheduler fires (continue-on-sample-error is set, so open requests fail rather than hang the shutdown).
- Pacing enforced per iteration (whole scenario), not per sampler.
- If a true arrival-rate/open model is needed instead of a closed-user model, that is a separate design and should replace this section rather than being mixed into it.

### 4.2 Scenario Orchestration

- Scenario selection uses **stock Throughput Controllers** (one per scenario), each in "Percent Executions" mode with its `percentThroughput` bound to `${__P(Sc{NN}.weight)}`.
- Distribution modes:
  - `weighted` → `scenarios[].weight` values pass through to the Throughput Controllers as percentages; set them to sum to 100 for a clean distribution.
  - `sequential` → config loader publishes `100 / N` for every enabled scenario, giving probabilistic equal share. This is **not** the deterministic round-robin the BlazeMeter Weighted Switch Controller plugin used to provide; determinism is a plugin-specific property and does not survive the switch to stock controllers.
- Each Throughput Controller decides independently per thread-group iteration, so any given iteration may execute 0, 1, or multiple scenarios. Over the test duration, scenario counts converge to the configured percentages. Pacing is per-scenario (§4.8), so individual scenario timings are unaffected by sibling TC decisions.
- Each scenario is a Transaction Controller with generate-parent-sample enabled and timer duration included in the parent sample, so scenario-level results reflect the full paced session duration.
- Scenarios defined once inside a disabled **Test Fragment**, referenced from each Throughput Controller via a **Module Controller**.

### 4.3 Data Handling

- CSV Data Set Config per scenario.
- File location: `data/{ScID}_{Purpose}.csv` (relative to the `.jmx` directory; JMeter resolves via its FileServer base dir).
- Sharing mode: **All threads** (default); recycle on EOF: **true**; stop thread on EOF: **false**.
- Destructive consumption deferred to v2.

### 4.4 Results Collection

- CLI only; no-op in GUI.
- Launcher creates:
  - `resultsRootDir` — default `./results/`
  - `runDir = ./results/{projectName}_{yyyyMMdd_HHmmss}/`
- Each successful CLI run produces `runDir/` containing:
  1. `raw.jtl` — test results (written by JMeter via `-l`)
  2. `jmeter.log` — run log (written by JMeter via `-j`)
  3. `effective-config.json` — resolved profile + env + CLI overrides + derived values used for the run
  4. `report/` — HTML dashboard (generated by JMeter CLI via `-e -o`)
  5. `custom/` — sweep target for scenario-written files
- No run ever overwrites a prior run.
- Bundled archiver is out of scope for v1 (the host environment doesn't ship a usable zip tool, and the in-JMeter options can't capture the post-tearDown HTML report). Users zip the `runDir/` manually when shipping results.

### 4.5 Execution Helper — `Test_executor.bat`

```
Test_executor.bat --profile <name> --env <name> --project <name>
                  [--mode weighted|sequential]
                  [--proxy-host <host> --proxy-port <port>]
                  [--results-root <path>]
                  [--help]
```

- Args translate to `-J` properties plus fixed CLI flags for JMeter output locations.
- `--proxy-host` and `--proxy-port` must be supplied together when proxying is enabled.
- Creates `runDir` before invocation.
- Invokes `jmeter.bat -n -t jmeter.jmx -l "{runDir}/raw.jtl" -j "{runDir}/jmeter.log" -e -o "{runDir}/report" -J<key>=<value>...`.
- Keeps batch responsibilities operational only: arg parsing, run-dir creation, JMeter invocation, exit-code propagation.

### 4.6 Logging & Debugging

- Logging module loaded in setUp, stored as `props["log"]`:
  - `log.info(where, msg)`, `log.warn(where, msg)`, `log.error(where, msg)`; one-argument `log.info(msg)` shorthand uses `-` as the context.
  - `log.banner(title, map)` — ANSI-colored boxed key/value output
  - `log.table(rows)` — pretty-printed tabular data
  - `log.errorSummary(scenario, step, expected, actual, hint)` — tester-friendly failure line
- Logging helpers must be thread-safe; JMeter worker threads will call them concurrently.
- Line format: `[yyyy-MM-dd HH:mm:ss] [LEVEL] [scenario/step] message`
- `logging.level` defaults to `INFO`; `-Jlog.level=INFO|WARN|ERROR` overrides it.
- ANSI colors use profile `logging.colors` as the base; `-Jlog.colors=true|false` overrides it. If neither is set, `System.getenv("WT_SESSION")` auto-enables colors in Windows Terminal and plain text is used elsewhere.
- GUI mode:
  - Truncates `jmeter.log` at setUp.
  - Auto-loads `debug.json` when `-Jprofile` is unset.
  - `-J` properties always override profile values.
- Config banner printed at setUp (CLI only).

### 4.7 Default Components (root of `.jmx`)

- HTTP Request Defaults (scheme/host/port bound to env resolution)
- HTTP Header Manager (common headers)
- HTTP Cache Manager
- HTTP Cookie Manager (per-thread cookies)
- User Defined Variables
- setUp Thread Group — config loader + banner
- Main Thread Group — stock Thread Group (scheduler-controlled, continue-on-sample-error)
- tearDown Thread Group — results finalization

**Listeners** (View Results Tree, Aggregate Report): **disabled** by default in the `.jmx`. Enabled manually in GUI during debugging. CLI runs use the `-l` flag for results output; no listener tree traversal needed. This matches the JMeter best-practice guidance.

### 4.8 Error Handling

- Assertion failures do not break the pacing loop.
- Pacing mechanism (four elements per scenario):
  1. **JSR223 PreProcessor** on the first sampler of the scenario: records `vars.putObject("iterStart", System.currentTimeMillis())`.
  2. **JSR223 PostProcessor** on the last sampler of the scenario: computes `remaining = pacingMs − (now − iterStart)`, stores in `vars.put("DELAY_TIME", String.valueOf(Math.max(remaining, 0)))`, logs a WARN pacing breach (with overage) when `remaining < 0`.
  3. **Flow Control Action (Pause)** as the last child of the scenario's Transaction Controller, with pause duration `0`.
  4. **Constant Timer** as a child of that Flow Control Action, with delay `${DELAY_TIME}`.
- This pattern works because JMeter Timers execute before the sampler in their scope. The Flow Control Action provides a sampler-shaped anchor at the end of the scenario so the dynamic delay is applied after the last real request.
- Breach warnings appear in both `jmeter.log` and stdout.

### 4.9 Proxy Support

- HTTP Request Defaults fields bound to `${__P(proxy.host,)}` / `${__P(proxy.port,)}`.
- Unset by default; enabled via launcher args.
- Proxy auth (`--proxy-user`, `--proxy-pass`) not in v1 — add when needed.

### 4.10 Test Fragments

Included, disabled by default, under a dedicated Fragments subtree:

- **Log to File (Groovy)** — writes a line to `${runDir}/custom/{scenario}.log` using a reusable writer stored in `props`; if `runDir` is unset (GUI), it warns and no-ops.
- **Proxy-aware HTTP Request** — example using proxy properties.
- **Assertion patterns** — status-only, body-contains, JSON-path.
- **Scenario Bodies** — `Sc01`, `Sc02`, ... Transaction Controllers live here; Module Controllers in the main orchestrator reference them.

### 4.11 Assertions

Every sampler under the Main Thread Group (scenario samplers + pacing anchor's enclosing TC) must have at least one assertion. The setUp/tearDown JSR223 samplers are exempt — they set their own `SampleResult.successful` from script and are not graded against protocol assertions.

## 5. Project Structure

```
/template/
    /data/
        Sc01_SomeData.csv
    /profiles/
        Load.json
        Soak.json
        Smoke.json
        Stress.json
        Breakpoint.json
        debug.json
    /results/
        /template_20260422_153403/
            raw.jtl
            jmeter.log
            effective-config.json
            report/
                index.html
                ...
            custom/
    jmeter.jmx
    Test_executor.bat
    environmentVariables.json
```

## 6. File Schemas

### 6.1 `environmentVariables.json`

```json
{
  "environments": {
    "dev":     { "scheme": "https", "host": "dev.example.com",     "port": 443 },
    "staging": { "scheme": "https", "host": "staging.example.com", "port": 443 },
    "prod":    { "scheme": "https", "host": "www.example.com",     "port": 443 }
  }
}
```

V1 contains servers only. Map-of-maps shape allows per-env additions (auth endpoints, region identifiers, etc.) without migration.

### 6.2 Profile JSON — `/profiles/*.json`

```json
{
  "profileName": "Load",
  "description": "Steady-state load, 1h hold",
  "mode": "weighted",
  "load": {
    "targetSessionsPerHour": 120,
    "sessionDurationSeconds": 600,
    "rampUpSeconds": 60,
    "holdSeconds": 3600,
    "rampDownSeconds": 60,
    "estimatedIterationSeconds": 30
  },
  "scenarios": [
    { "id": "Sc01", "weight": 70 },
    { "id": "Sc02", "weight": 30 }
  ],
  "logging": {
    "level": "INFO",
    "colors": true
  }
}
```

Semantics:

- `rampDownSeconds` → at-capacity tail window (stock Thread Group has no gradual ramp-down); scheduler duration = `rampUpSeconds + holdSeconds + rampDownSeconds`.
- `scenarios[].weight` → percent of iterations that should run the scenario (consumed by a per-scenario Throughput Controller). Set weights to sum to 100 for a clean distribution.
- For `mode: "sequential"`, the config loader ignores `scenarios[].weight` and publishes `100 / N` for every enabled scenario (probabilistic equal share, not deterministic round-robin).

Profile type conventions:

| Profile | Users | Duration | Purpose |
|---|---|---|---|
| `Smoke` | 1 | Short run | Sanity check after changes |
| `debug` | 1 | Long-running / manual stop | GUI development |
| `Load` | Nominal | 1h hold | Representative load |
| `Stress` | Above nominal | 30m–1h | Find degradation point |
| `Soak` | Nominal | 8h+ | Detect leaks / drift |
| `Breakpoint` | Ramp | Until failure | Determine capacity ceiling |

### 6.3 Property Reference — `-J` flags

| Property | Source | Purpose |
|---|---|---|
| `profile` | `--profile` | Profile name; resolves to `/profiles/{name}.json` |
| `env` | `--env` | Environment key in `environmentVariables.json` |
| `projectName` | `--project` | Used in results folder name |
| `mode` | `--mode` (optional) | Overrides profile's `mode` |
| `proxy.host` | `--proxy-host` (optional) | HTTP proxy host |
| `proxy.port` | `--proxy-port` (optional) | HTTP proxy port |
| `log.level` | (optional) | Override profile logging level (`INFO`, `WARN`, `ERROR`) |
| `log.colors` | (optional) | Force ANSI on/off |
| `runDir` | launcher-generated | Per-run output directory passed into JMeter |

`--results-root` is a launcher-only flag (controls where `runDir` is created); it is **not** passed to JMeter as a `-J` property.

GUI defaults (when `-J` unset): `profile=debug`, `env=dev`, `projectName=debug`.

## 7. Runtime Contracts

### 7.1 Config Banner (setUp, CLI only)

```
╔══════════════════════════════════════════════════════════╗
║  JMeter Run Configuration                                ║
╠══════════════════════════════════════════════════════════╣
║  Project           : acme                                ║
║  Profile           : Load                                ║
║  Environment       : dev (https://dev.example.com:443)   ║
║  Mode              : weighted                            ║
║  Concurrent users  : 20                                  ║
║  Sessions/hour     : 120                                 ║
║  Session target (s): 600                                 ║
║  Think time budget : 570.0 (est. iter = 30s)             ║
║  Ramp / Hold / Tail: 60 / 3600 / 60                      ║
║  Scenarios         : Sc01 (70%), Sc02 (30%)              ║
╚══════════════════════════════════════════════════════════╝
```

### 7.2 Log Line Format

```
[2026-04-22 15:34:03] [INFO]  [Sc01/step2] Submitting order payload
[2026-04-22 15:44:04] [WARN]  [Sc01]       Pacing breach: iteration 631.4s, target 600s, overage 31.4s
[2026-04-22 15:44:05] [ERROR] [Sc01/step3] Expected 200, got 502 — server may be overloaded
```

### 7.3 Fatal Config Error Format

```
[FATAL] Missing profile key: load.targetSessionsPerHour
[FATAL] Unknown environment: staging2 (available: dev, staging, prod)
```

### 7.4 Results Folder Guarantees

Per successful CLI run: exactly one `runDir/`. No collisions, no overwrites. GUI runs produce nothing.

## 8. Implementation Phases

Sequential. Each phase's acceptance check must pass before the next begins.

### Phase 1 — Skeleton

Deliverables:
- Folder tree populated.
- `environmentVariables.json` with `dev`, `staging`, `prod`.
- Six stub profile files.
- `Test_executor.bat` arg parser + `runDir` creation + `--help`.
- `jmeter.jmx` with root-level defaults (§4.7), empty setUp/Main/tearDown thread groups, empty Fragments subtree.

Acceptance: GUI opens `.jmx` with no validation errors; zero-thread run completes; tearDown placeholder fires.

### Phase 2 — Config Loader + Banner

Deliverables:
- setUp Groovy reads `-Jprofile` and `-Jenv`; loads profile and environment JSON.
- Validates required keys; fails fast with named missing key (§7.3).
- Computes `concurrentUsers`, pacing, and think-time values (§4.1).
- Publishes values to `props`, including per-scenario weights as `Sc01.weight`, `Sc02.weight`, ... and writes `effective-config.json` into `runDir`.
- Banner printer (§7.1).

Acceptance: `jmeter -n -t jmeter.jmx -Jprofile=Load -Jenv=dev -JprojectName=acme` prints correct banner; removing a required key reproduces the exact fatal error format.

### Phase 3 — Sc01 End-to-End

Deliverables:
- Sc01 Transaction Controller (generate parent: true, include timers: true) in the Fragments subtree, containing a short 3-sampler scaffold. Adapted project scenarios still expand or replace this scaffold to meet the 15–25 call target in §3.
- Response Assertion on each sampler.
- Constant Timer between samplers using `thinkTimeBudgetMs / max(nSamplers − 1, 1)`.
- Pacing per §4.8 (PreProcessor, PostProcessor, Flow Control Action + child Constant Timer).
- Main Thread Group references Sc01 via a single Module Controller for now.

Acceptance: happy-path run shows per-iteration pacing within ±100ms of target; forced 500 response still triggers full pacing wait; artificially slowed scenario produces breach warning in both log and stdout.

### Phase 4 — Orchestration

Deliverables:
- Sc02 Transaction Controller mirroring Sc01 (in Fragments).
- One stock Throughput Controller per scenario as siblings under the Main Thread Group, each wrapping a Module Controller pointing at the scenario's Fragment.
- Throughput Controllers set to "Percent Executions" mode, `perThread=false`; `percentThroughput` bound to `${__P(Sc01.weight)}`, `${__P(Sc02.weight)}`.
- `mode=sequential` causes the config loader to publish `100 / N` for every enabled scenario.

Acceptance: 70/30 weighted run over ≥1000 iterations matches expected counts within ±3%; equal-share (`sequential`) run over ≥1000 iterations matches 50/50 within ±3% (probabilistic, not deterministic).

### Phase 5 — tearDown Pipeline

Deliverables:
- GUI detection guard: `GuiPackage.getInstance() != null` → early return.
- tearDown finalizes only JMeter-internal artifacts: close any shared writers, ensure `${runDir}/custom/` is flushed, emit summary log line.
- Launcher-generated `-e -o` produces the HTML report in `${runDir}/report/`.

Acceptance: CLI run produces one new folder; consecutive runs do not collide; GUI run produces nothing.

### Phase 6 — Logging Library + GUI Behaviors

Deliverables:
- Logging module per §4.6.
- GUI auto-load of `debug.json` when `-Jprofile` unset.
- GUI-mode `jmeter.log` truncation at setUp.
- Override precedence: profile is base, `-J` overrides.
- Friendly error summaries on assertion failure, hooked via a JSR223 Listener that inspects `AssertionResult[]` on each sample and emits a summary only on failure.

Acceptance: cold GUI open → debug loaded and log empty; `-Jprofile=Load` in GUI → Load wins; forced assertion failure → one summary line appears with expected/actual/hint.

### Phase 7 — Fragments + Proxy

Deliverables:
- Fragments per §4.10 (Log to File, Proxy-aware HTTP Request, Assertion patterns).
- HTTP Request Defaults wired to `${__P(proxy.host,)}` / `${__P(proxy.port,)}`.

Acceptance: enabling the Log to File fragment inside Sc01 writes to `${runDir}/custom/Sc01.log`; `--proxy-host 127.0.0.1 --proxy-port 8888` routes traffic through local proxy (verified via Fiddler or similar).

### Phase 8 — Documentation

Deliverables:
- **Usage Guide** covering template concept, folder structure, full profile schema with annotated example of each profile type, pacing math, distribution modes, HAR → JMX via BlazeMeter (`https://converter.blazemeter.com/`) with cleanup checklist (strip static assets, tracking, third-party requests), CSV data conventions, proxy usage.
- **Execution Guide** covering the Record/Build/Debug/Execute flow, GUI runs, CLI via `Test_executor.bat` with full arg reference, reading the results folder, interpreting pacing breach warnings.
- Inline `.jmx` comments — every JSR223 block has a header comment stating purpose, `props`/`vars` read, and values written.

Acceptance: a new tester configures and runs a test unassisted.

## 9. Decisions Log

| # | Decision | Outcome |
|---|---|---|
| 1 | Java | 17 LTS (JDK) |
| 2 | Distribution | Sibling stock Throughput Controllers (percent mode) — one per scenario; weights are percentages; `sequential` publishes equal `100/N` share (probabilistic, not deterministic round-robin) |
| 3 | Destructive data | Deferred to v2 |
| 4 | Pacing breach | Always honor pacing; if iteration overruns, log WARN and continue immediately |
| 5 | Listener presence | Disabled by default in `.jmx`; enabled manually in GUI; CLI uses `-l` flag |
| 6 | `environmentVariables.json` | `{ environments: { name: { scheme, host, port } } }` — servers only for v1 |
| 7 | HAR tooling | BlazeMeter converter (`https://converter.blazemeter.com/`) |
| 8 | Orchestration split | Thin `.bat` launcher for run-dir creation, JMeter invocation, and report output; Groovy for config/load-time logic only |
| 9 | Scenario reuse | Module Controllers referencing once-defined Transaction Controllers inside a Fragments subtree |
| 10 | Override precedence | Profile file is base; `-J` properties override |
| 11 | Ramp control | Stock Thread Group with scheduler enabled; `duration = rampUpSeconds + holdSeconds + rampDownSeconds` because stock Thread Group Duration is total lifetime after startup delay. No gradual ramp-down (rampDown is an at-capacity tail window before a hard stop) |
| 12 | Scenario reporting | Transaction Controller, generate-parent-sample = true |
| 13 | Think time distribution | Constant Timer between samplers; total budget = sessionDuration − est. iter time, divided by `(n−1)` |
| 14 | Assertion failure → friendly log | JSR223 Listener inspecting `AssertionResult[]`, emits one-line summary |
| 15 | Pacing mechanism | JSR223 PreProcessor (first sampler, records start) + JSR223 PostProcessor (last sampler, computes `DELAY_TIME`) + Flow Control Action Pause (`0`) + child Constant Timer (`${DELAY_TIME}`) |
| 16 | HTML report generation | JMeter CLI `-e -o` into `${runDir}/report/` |
| 17 | Zip mechanism | Out of scope for v1 — host env blocks `tar.exe`, and the only Groovy hook (tearDown) runs before JMeter emits the HTML report. Users zip `runDir/` manually if they need an archive |
| 18 | CSV sharing | All threads / recycle on EOF / don't stop thread on EOF |
| 19 | Launcher timestamp | Prefer Java 17 source-file timestamp helper; fall back to deprecated `wmic` and then common `%DATE%/%TIME%` formats; never use PowerShell |
| 20 | Logging overrides | Profile logging config is the base; `-Jlog.level` / `-Jlog.colors` override; logger writes full contextual lines to both stdout and `jmeter.log` |
| 21 | Scenario parent timing | Transaction Controller parent samples include timers so scenario samples reflect full paced session duration |
| 22 | Scenario scaffold size | Committed Sc01/Sc02 are short scaffolds for template mechanics; adapted project scenarios should expand/replace them with 15–25 meaningful HTTP calls |
| 23 | Drop plugin dependencies | Template uses stock JMeter 5.6.3 only. Ultimate Thread Group replaced by stock Thread Group + scheduler; Weighted Switch Controller replaced by per-scenario Throughput Controllers. Tradeoff: no gradual ramp-down, `sequential` becomes probabilistic equal-share. Driver: users cannot reliably get plugin installs approved in locked-down environments |

## 10. Open Questions

- Should `targetSessionsPerHour` mean a **closed-model completed-session target** (the model assumed in this plan), or do you actually want a **true arrival-rate model**? If it is the latter, the load-shaping section should switch away from stock Thread Group + scheduler to an arrivals/open-model design (stock Concurrency Thread Group is also a plugin, so a true open model likely needs a plugin exemption) instead of keeping the current math.

## 11. References

### Apache JMeter

- [User Manual — Index](https://jmeter.apache.org/usermanual/index.html)
- [Getting Started / CLI mode](https://jmeter.apache.org/usermanual/get-started.html)
- [Best Practices](https://jmeter.apache.org/usermanual/best-practices.html)
- [Test Plan Elements](https://jmeter.apache.org/usermanual/test_plan.html)
- [Component Reference](https://jmeter.apache.org/usermanual/component_reference.html) — covers Transaction Controller, Flow Control Action, JSR223 elements, Response Assertion, Constant/Uniform Random Timers, CSV Data Set Config
- [Functions Reference](https://jmeter.apache.org/usermanual/functions.html) — covers `__P`, `__groovy`, `__time`
- [Properties Reference](https://jmeter.apache.org/usermanual/properties_reference.html)
- [Generating the HTML Dashboard Report](https://jmeter.apache.org/usermanual/generating-dashboard.html)
- [Build a Web Test Plan](https://jmeter.apache.org/usermanual/build-web-test-plan.html)
- [Glossary](https://jmeter.apache.org/usermanual/glossary.html)
- [ReportGenerator API Javadoc](https://jmeter.apache.org/api/org/apache/jmeter/report/dashboard/ReportGenerator.html)

### Tooling

- [BlazeMeter JMX Converter (HAR → JMX)](https://converter.blazemeter.com/)
- [BlazeMeter — HAR to JMX workflow guide](https://help.blazemeter.com/docs/guide/integrations-jmx-converter.htm)

### Background reading

- [BlazeMeter — JMeter Non-GUI Mode tips](https://www.blazemeter.com/blog/jmeter-non-gui-mode) — best practice context for the `-l` flag and listener avoidance
- [Community pattern — iteration pacing via Flow Control Action](https://automationsolutions.org/2021/10/28/implementing-iteration-pacing-in-jmeter/) — the pattern adopted in §4.8
