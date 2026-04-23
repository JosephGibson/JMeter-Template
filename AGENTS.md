# AGENTS.md

LLM operating rules for this repo.

## Read order

1. [jmeter-template-plan.md](jmeter-template-plan.md) — authoritative spec
2. [README.md](README.md) — quick orientation
3. [docs/LLM_INDEX.md](docs/LLM_INDEX.md) — file map

The plan is the source of truth. README/AGENTS/INDEX must not contradict it; if they drift, the plan wins and the others are corrected.

## Hard constraints (from plan §3)

- One `.jmx` per project. Reuse pattern is copy-and-modify, not parameterize.
- No code duplication across scenarios — share via Test Fragments + Module Controllers.
- Scenario IDs: `Sc01`, `Sc02`, ... (zero-padded, two digits).
- Adapted project scenarios should contain 15–25 meaningful HTTP calls. The committed Sc01/Sc02 flows are short scaffolds for template mechanics and are expanded or replaced during project build-out.
- Dev flow: Record → Build in GUI → Debug in GUI → Execute in CLI.
- HAR is the primary recording input (BlazeMeter converter).
- **No PowerShell.** Launcher is `.bat` only.
- Every sampler under the Main Thread Group must have at least one assertion. setUp/tearDown JSR223 samplers are exempt (they set their own `SampleResult.successful`).
- Listeners disabled by default in `.jmx`; CLI uses `-l` flag.
- No run ever overwrites a prior run.

## Implementation discipline

- Phases (plan §8) are sequential. Do not start phase N+1 until phase N's acceptance check passes.
- Profile is base config; `-J` properties override.
- `.bat` launcher is operational only: arg parsing, run-dir creation, JMeter invocation, exit propagation. No business logic.
- Groovy handles config/load-time logic and logging only.
- Pacing mechanism is fixed: PreProcessor + PostProcessor + Flow Control Action Pause(0) + child Constant Timer (plan §4.8). Do not substitute alternatives.
- Closed-user model is the default load shape. An open/arrival-rate model is a separate design that *replaces* §4.1, not mixed into it (plan §10).

## When editing the plan

- Update the Decisions Log (plan §9) when a design choice changes.
- If a phase's acceptance criteria change, revise §8 explicitly — do not let drift accumulate.
- Append a `[Unreleased]` entry to [CHANGELOG.md](CHANGELOG.md) for any user-visible change.

## Scope guardrails

Do not add: destructive CSV consumption (deferred to v2), proxy auth (`--proxy-user`/`--proxy-pass`), arrival-rate load model, additional environments beyond `dev`/`staging`/`prod` unless asked.
