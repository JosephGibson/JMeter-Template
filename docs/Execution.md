# Execution Guide

How to take the template from recording through CLI execution and result review.

## 1. Dev flow — Record → Build → Debug → Execute

The template is designed around a single loop:

1. **Record** a single user session as a HAR (browser DevTools → Network → Export HAR).
2. **Build** in the JMeter GUI:
   - Convert HAR → JMX via [BlazeMeter](https://converter.blazemeter.com/).
   - Copy cleaned samplers into `Sc{NN}` inside the Fragments subtree (see [Usage § 6 / § 8](Usage.md)).
   - Wire a Module Controller + Weighted Switch Controller row as described in Usage § 6.
3. **Debug** in the JMeter GUI:
   - Open `jmeter.jmx`; no `-J` props ⇒ `profile=debug`, `env=dev`, `projectName=debug` are auto-applied.
   - Temporarily enable `View Results Tree` and/or `Aggregate Report` for visibility. **Disable them before CLI runs** (plan §4.7).
   - Run once. Fix assertion failures, adjust think times, verify pacing.
4. **Execute** in CLI via `Test_executor.bat`.

## 2. GUI runs

Open `jmeter.jmx` in the JMeter GUI (5.6.3 + Ultimate Thread Group + Weighted Switch Controller plugins).

- **Defaults when no `-J` props are set**: `profile=debug`, `env=dev`, `projectName=debug`.
- `-J` properties always override profile values (Decision #10).
- Override precedence: profile file is base; `-J` wins.
- The detected `jmeter.log` candidates are truncated at setUp so each GUI run starts fresh.
- The banner does **not** print in GUI (only in CLI).
- GUI runs do not produce `runDir/`.

To run a specific profile in GUI, start the GUI with `-J` properties on the command line:

```
jmeter.bat -Jprofile=Load -Jenv=dev -JprojectName=acme
```

## 3. CLI runs — `Test_executor.bat`

```
Test_executor.bat --profile <name> --env <name> --project <name>
                  [--mode weighted|sequential]
                  [--proxy-host <host> --proxy-port <port>]
                  [--results-root <path>]
                  [--help]
```

| Arg | Required | Purpose |
|---|---|---|
| `--profile`      | yes | Profile name; resolves to `profiles/<name>.json`. |
| `--env`          | yes | Environment key in `environmentVariables.json`. |
| `--project`      | yes | Project name; used in the results folder name. |
| `--mode`         | no  | Overrides profile's `mode` (`weighted`\|`sequential`). |
| `--proxy-host`   | no  | HTTP proxy host (pair with `--proxy-port`). |
| `--proxy-port`   | no  | HTTP proxy port. |
| `--results-root` | no  | Override default `./results/`. |
| `--help` / `-h`  | no  | Print usage. |

Example:

```
Test_executor.bat --profile Load --env staging --project acme
Test_executor.bat --profile Smoke --env dev --project acme --mode sequential
Test_executor.bat --profile Load --env dev --project acme --proxy-host 127.0.0.1 --proxy-port 8888
```

The launcher:

1. Validates required args.
2. Resolves a `yyyyMMdd_HHmmss` timestamp via Java 17, with deprecated `wmic` and common `%DATE%/%TIME%` formats as fallbacks. PowerShell is never used.
3. Creates `runDir = results/<project>_<yyyyMMdd_HHmmss>/` (fails if it already exists).
4. Invokes `jmeter.bat -n -t jmeter.jmx -l raw.jtl -j jmeter.log -e -o report -J...`.
5. Propagates JMeter's exit code.

No run ever overwrites a prior run (plan §7.4). Retry failures always get a fresh timestamp and fresh folder. The launcher does not archive `runDir/`; zip manually (Windows Explorer → Send to → Compressed folder) when shipping results.

## 4. Reading the results folder

```
results/acme_20260422_153403/
├── raw.jtl                   Raw JMeter results (CSV-formatted sample log)
├── jmeter.log                JMeter run log (INFO/WARN/ERROR from samplers and the logger module)
├── effective-config.json     Snapshot of the resolved config used for this run
├── report/                   JMeter HTML dashboard
│   ├── index.html
│   ├── content/
│   └── sbadmin2-1.0.7/
└── custom/                   Scenario-written files (if the Log to File fragment was enabled)
```

### What to check first

1. **`report/index.html`** — summary KPIs: errors, response time percentiles, throughput. Open in browser.
2. **`effective-config.json`** — confirms profile + env + overrides + derived values used for the run. Paste into bug reports.
3. **`jmeter.log`** — grep for `[ERROR]` and `[WARN]`. `[WARN] Pacing breach` is the key signal that the system cannot keep up (§5 below).
4. **`raw.jtl`** — for deep dives. Load into Excel / a fresh JMeter GUI instance's View Results Tree for drill-down.

### effective-config.json shape

Fields are the union of the profile, environment, resolved mode, derived values, scenarios with runtime weights, and the resolved proxy block. Example:

```json
{
  "project": "acme",
  "profile": { "name": "Load", "description": "Steady-state load, 1h hold", "source": "C:\\...\\profiles\\Load.json" },
  "mode": "weighted",
  "environment": { "name": "dev", "scheme": "https", "host": "dev.example.com", "port": 443 },
  "load": { "targetSessionsPerHour": 120, "sessionDurationSeconds": 600, "rampUpSeconds": 60, "holdSeconds": 3600, "rampDownSeconds": 60, "estimatedIterationSeconds": 30 },
  "derived": { "concurrentUsers": 20, "pacingSeconds": 600.0, "thinkTimeBudgetSeconds": 570.0 },
  "scenarios": [ { "id": "Sc01", "weight": 70 }, { "id": "Sc02", "weight": 30 } ],
  "logging": { "level": "INFO", "colors": true },
  "proxy": { "host": null, "port": null }
}
```

## 5. Interpreting pacing breach warnings

A **pacing breach** is a scenario iteration that took longer than `pacingSeconds`. The PostProcessor emits:

```
[2026-04-22 15:44:04] [WARN ] [Sc01] Pacing breach: iteration 631.4s, target 600s, overage 31.4s
```

Meaning: **your iteration overran the target session duration by 31.4 s**. The pacing timer skips the wait for this iteration (honors the rule *always honor pacing; continue immediately*, Decision #4).

Causes, in rough order of likelihood:

| Cause | Evidence | Fix |
|---|---|---|
| Server slow | Response time percentiles climb; 5xx or timeouts in `raw.jtl` | Reduce `targetSessionsPerHour`, or investigate the system under test |
| `estimatedIterationSeconds` set too low | Consistent small overages even at light load | Raise `estimatedIterationSeconds` (it *only* affects think-time budget, not pacing target) |
| Think time math off | Overages proportional to think time | Reduce think time between samplers or extend `sessionDurationSeconds` |
| External dependency (proxy, DNS) | Tail latencies in specific samplers | Check proxy logs, network path, or run without proxy |

Note: a single breach is normal noise. **Sustained breaches** (>5 % of iterations, or breaches that grow over time) indicate the system can't sustain the requested rate.

## 6. Exit codes

| Exit | Source | Meaning |
|---|---|---|
| `0`  | launcher | Success |
| `1`  | launcher | Arg parse failure (missing/invalid flag) |
| `2`  | launcher | Missing file: profile, environmentVariables.json, or jmeter.jmx |
| `3`  | launcher | Could not compute timestamp |
| `4`  | launcher | `runDir` already exists (timestamp collision — shouldn't happen) |
| `<n>` | JMeter  | JMeter's own exit code |

## 7. Common pitfalls

- **Forgetting `-n`** — all CLI use runs through `Test_executor.bat`, which supplies `-n`. Do not invoke `jmeter.bat` directly unless you know why.
- **Running with listeners enabled** — kills throughput. Disable `View Results Tree` / `Aggregate Report` before CLI runs; they are disabled in the committed `.jmx` by default.
- **Checking `report/` before the run finishes** — JMeter generates the HTML dashboard after the run ends. During the run, only `raw.jtl` and `jmeter.log` are live.
- **Assuming sequential mode means one-at-a-time** — `sequential` is *scenario selection order*, not user concurrency. You still run `concurrentUsers` threads; they just rotate through scenarios deterministically.
- **Changing `sessionDurationSeconds` without changing `targetSessionsPerHour`** — both feed `concurrentUsers`, so changing one changes user count. Adjust deliberately.
