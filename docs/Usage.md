# Usage Guide

Target audience: a tester adapting this template for a new API/webflow project.

## 1. Template concept

The template is a **single, reusable `.jmx`** configured entirely from JSON profile files and `-J` properties. One project gets one copy of the `.jmx`; reuse across projects happens by **copy-and-modify**, not by parameterization.

Hard rules (plan §3):

- One `.jmx` per project.
- No code duplication across scenarios — share via Test Fragments + Module Controllers.
- Scenario IDs: `Sc01`, `Sc02`, ... (zero-padded, two digits).
- Adapted project scenarios should contain 15–25 meaningful HTTP calls; the committed Sc01/Sc02 flows are short scaffolds for template mechanics.
- Every sampler has at least one assertion.
- Listeners disabled in the `.jmx`; CLI writes JTL via `-l`.
- No run ever overwrites a prior run.

## 2. Folder structure

```
{projectName}/
├── jmeter.jmx                    # Test plan (one per project)
├── Test_executor.bat             # Launcher (arg parsing, runDir, JMeter invocation)
├── environmentVariables.json     # dev / staging / prod servers
├── data/
│   └── Sc{NN}_{Purpose}.csv      # Per-scenario CSV inputs
├── profiles/
│   ├── Load.json
│   ├── Soak.json
│   ├── Smoke.json
│   ├── Stress.json
│   ├── Breakpoint.json
│   └── debug.json
└── results/
    └── {project}_{yyyyMMdd_HHmmss}/   # runDir per successful CLI run
        ├── raw.jtl
        ├── jmeter.log
        ├── effective-config.json
        ├── report/index.html
        └── custom/                    # scenario-written files
```

## 3. Profile schema

Each profile is a JSON file in `profiles/`. Full schema (plan §6.2):

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

Field reference:

| Field | Meaning |
|---|---|
| `profileName` | Human-readable profile label |
| `description` | Free-form description used in banners and reports |
| `mode` | `weighted` or `sequential`; overridable via `--mode` |
| `load.targetSessionsPerHour` | Tester-facing throughput target (completed sessions / hour) |
| `load.sessionDurationSeconds` | One iteration's target wall-clock time = pacing interval |
| `load.rampUpSeconds` | Startup window for Ultimate Thread Group |
| `load.holdSeconds` | Hold window at full concurrency |
| `load.rampDownSeconds` | Shutdown window |
| `load.estimatedIterationSeconds` | Rough time all samplers consume; feeds the think-time budget |
| `scenarios[].id` | Scenario ID, must match a Transaction Controller in the Fragments subtree |
| `scenarios[].weight` | Used only when `mode: "weighted"`; must be `> 0` |
| `logging.level` | `INFO` / `WARN` / `ERROR`; `-Jlog.level` overrides |
| `logging.colors` | Force ANSI colors; `-Jlog.colors` overrides |

In `sequential` mode the loader ignores `weight` and publishes `1` for every scenario, which makes the Weighted Switch Controller deterministic round-robin (plan §4.2).

### Annotated profile types

| Profile | Typical shape | Purpose |
|---|---|---|
| `Smoke` | 1 user, 1 loop | Sanity check after changes. Short hold, no ramp. |
| `debug` | 1 user, open-ended | GUI development; auto-loaded when `-Jprofile` is unset. |
| `Load` | Nominal throughput, 1h hold | Representative production load. |
| `Stress` | Above nominal, 30m–1h | Find the degradation point. |
| `Soak` | Nominal, 8h+ | Detect leaks / drift. |
| `Breakpoint` | Ramp until failure | Determine capacity ceiling; very long rampUp, short hold. |

## 4. Pacing math (closed-user model, plan §4.1)

A JMeter **thread is one user session**. Each iteration of the thread runs **one scenario**.

Derived at runtime from the profile's `load.*` inputs:

```
concurrentUsers        = max(1, ceil(targetSessionsPerHour * sessionDurationSeconds / 3600))
pacingSeconds          = sessionDurationSeconds
thinkTimeBudgetSeconds = max(sessionDurationSeconds - estimatedIterationSeconds, 0)
```

Worked example for `targetSessionsPerHour=120`, `sessionDurationSeconds=600`, `estimatedIterationSeconds=30`:

- `concurrentUsers = ceil(120 * 600 / 3600) = ceil(20) = 20`
- `pacingSeconds = 600`
- `thinkTimeBudgetSeconds = max(600 - 30, 0) = 570`

The **think time budget** is distributed across Constant Timers between samplers: `budget / (n-1)` for `n` samplers in the scenario (Decision #13). For 3 samplers this is 285 s between each step.

Each Think Timer is attached as a **child** of the sampler it should delay (step 2 onwards). This is deliberate: JMeter runs every in-scope timer before every sibling sampler, so placing timers at the Transaction Controller level would multiply their delay by the sampler count. When you expand a scenario, keep each Think Timer as a child of its "after" sampler and update the `intdiv(N)` divisor to `n-1`.

Actual pacing is enforced **per iteration**, not per sampler — a scenario that overruns its `sessionDurationSeconds` logs a WARN and continues immediately. The mechanism is four-element (plan §4.8):

1. JSR223 **PreProcessor** on first sampler → records `iterStart`.
2. JSR223 **PostProcessor** on last sampler → computes `DELAY_TIME = pacingMs − elapsed`.
3. **Flow Control Action Pause(0)** as last child of the Transaction Controller.
4. Child **Constant Timer** with `${DELAY_TIME}` delay.

The scenario Transaction Controller is configured to generate a parent sample and include timers, so scenario-level timings represent the full paced session duration.

## 5. Distribution modes

- **`weighted`**: each scenario's `weight` is used as its share (e.g. 70/30 → 70% Sc01, 30% Sc02 over many iterations).
- **`sequential`**: scenarios run deterministic round-robin (equal runtime weights fed into the Weighted Switch Controller with Random Choice off).

Override via `--mode weighted|sequential` (or `-Jmode=...`) without editing the profile.

## 6. Adding a new scenario

1. Record the flow as a HAR in your browser (DevTools → Network → export HAR).
2. Convert to JMX via the [BlazeMeter HAR-to-JMX converter](https://converter.blazemeter.com/).
3. Open the converted JMX — use it as a reference only.
4. **Clean up** the converted samplers (checklist in §8).
5. In your `jmeter.jmx` (GUI):
   - Duplicate `Sc01` Transaction Controller in the Fragments subtree and rename it `Sc{NN}`.
   - Paste your cleaned samplers in order.
   - Build out the real flow to 15–25 meaningful HTTP calls; the committed 3-call scaffolds are only placeholders.
   - Keep the PreProcessor on the first sampler and the PostProcessor on the last.
   - Place a Think Time Constant Timer as a **child** of each sampler from step 2 onwards (never as a Transaction Controller sibling — see §4), and update each timer's `intdiv(N)` to `N = nSamplers - 1`.
   - Keep the Pacing Anchor + Pacing Timer block at the end.
   - Add a Module Controller under the Weighted Switch Controller pointing at the new Transaction Controller; name it `Sc{NN}` (matching the WSC row name).
   - Add a new row to the Weighted Switch Controller's weights list: `Sc{NN}` → `${__P(Sc{NN}.weight,1)}`.
6. Add `scenarios[].id = Sc{NN}` to every profile you want it to run in. Give it a `weight` > 0 for weighted profiles.

## 7. CSV data conventions (plan §4.3)

- File path: `data/Sc{NN}_{Purpose}.csv`, e.g. `data/Sc01_Users.csv`. The path is relative to the `.jmx` directory; JMeter resolves it via its FileServer base dir.
- Add a **CSV Data Set Config** inside the scenario's Transaction Controller (one per scenario/CSV pair). A disabled template is in the Fragments subtree.
- Sharing mode: **All threads**.
- Recycle on EOF: **true**.
- Stop thread on EOF: **false**.
- First row is the header; values in `variableNames` must match.
- **No destructive consumption in v1.** If you need single-use data, plan §9 defers it to v2.

## 8. HAR → JMX cleanup checklist

Converted JMX files almost always contain noise that ruins assertions and inflates run times. Remove before committing:

- [ ] Static assets: CSS, JS, fonts, images (`.css`, `.js`, `.png`, `.woff2`, etc.) unless the flow genuinely depends on them.
- [ ] Third-party tracking: Google Analytics, Mixpanel, Segment, Hotjar, DataDog RUM.
- [ ] OPTIONS / CORS preflight requests (let HttpClient4 handle them, or drop if not meaningful).
- [ ] Ad network calls and social widget fetches.
- [ ] Browser-only endpoints: favicon, manifest, service worker.
- [ ] Duplicate calls generated by SPA re-renders.
- [ ] Hardcoded cookies and auth tokens — replace with variables / cookie manager.
- [ ] Hardcoded domains — clear the per-sampler domain so `HTTP Request Defaults` wins.
- [ ] Absolute URLs in paths — reduce to relative paths.
- [ ] Empty or zero-byte bodies on GETs.
- [ ] Response Assertions: each surviving sampler needs at least one (plan §4.11).

## 9. Proxy usage (plan §4.9)

For recording through Fiddler, mitmproxy, Charles, or similar:

```
Test_executor.bat --profile Smoke --env dev --project acme --proxy-host 127.0.0.1 --proxy-port 8888
```

Both args must be set together (v1 has no proxy auth). The HTTP Request Defaults is already wired to `${__P(proxy.host,)}` / `${__P(proxy.port,)}`, so every sampler inherits the proxy.

## 10. Logging

Logger installed at setUp and stored as `props["log"]`. Accessible from any JSR223 block:

```groovy
def log = props.get("log")
log.info("Loaded reusable fragment")
log.info("Sc01/step2",  "Submitting order payload")
log.warn("Sc01",        "Pacing breach: ...")
log.error("Sc01/step3", "Expected 200, got 502 — server may be overloaded")
log.banner("Config summary", [project: "acme", env: "dev"])
log.table([[url:"/a", ms:120], [url:"/b", ms:90]])
log.errorSummary("Sc01", "step3", "200", "502", "server may be overloaded")
```

Line format in stdout and the custom `jmeter.log` message: `[yyyy-MM-dd HH:mm:ss] [LEVEL] [scenario/step] message`.

`logging.level` / `logging.colors` from the profile are the base values. Override with `-Jlog.level=INFO|WARN|ERROR` or `-Jlog.colors=true|false`; if no colors value is set, Windows Terminal detection (`WT_SESSION`) enables ANSI automatically.
