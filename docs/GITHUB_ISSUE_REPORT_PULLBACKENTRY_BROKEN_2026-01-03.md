# GitHub Issue Report (Draft)

## Title
EA_PullbackEntry_v5_* fails to compile: `_Period` undeclared (vanilla MQL5)

## Summary
`EA_PullbackEntry_v5_*` uses `_Period` to build a hash key / log timeframe strings.
In a vanilla MetaTrader 5 / MQL5 environment, `_Period` is not guaranteed to be defined in this compile context, which causes MetaEditor compilation to fail with an undeclared identifier error and cascading failures.

The minimal, safe fix is to replace `_Period` usage with `Period()` and keep the cast explicit: `EnumToString((ENUM_TIMEFRAMES)Period())`.

## Repository / Branch / Commit
- Repo: `sawai-46/mt5-oanda-trader`
- Branch: `main`
- Commit (local HEAD when observed): `e5ed28b263e4942357641f30f82bc0342f48e012`
- Observed date: 2026-01-03

## Affected Files
- `mql5/Experts/EA_PullbackEntry_v5_FX.mq5`
- `mql5/Experts/EA_PullbackEntry_v5_JP225.mq5`
- `mql5/Experts/EA_PullbackEntry_v5_USIndex.mq5`

## Steps to Reproduce
1. Open the project in MetaEditor.
2. Compile any of the following EAs:
   - `EA_PullbackEntry_v5_FX.mq5`
   - `EA_PullbackEntry_v5_JP225.mq5`
   - `EA_PullbackEntry_v5_USIndex.mq5`

## Actual Result
Compilation error similar to (example from user report, EA_PullbackEntry_v5_FX.mq5):
- `undeclared identifier` (line 128)
- `'(ENUM_TIMEFRAMES)' - some operator expected` (line 128)
- `implicit conversion from 'unknown' to 'string'` (line 128)
and follow-up parser errors (semicolon expected, illegal operation, etc.).

## Expected Result
The EA compiles successfully without requiring any additional helper includes.

## Root Cause (Likely)
`GenerateMagicNumber()` (and related config logging) used `_Period` in expressions like `EnumToString((ENUM_TIMEFRAMES)_Period)`.
In this environment, `_Period` is not defined, so the cast/expression fails and triggers cascading syntax errors.

## Proposed Fix
Replace `_Period` usage with `Period()` and keep the cast explicit:

- `EnumToString((ENUM_TIMEFRAMES)Period())`

### Patch Summary
- Use `EnumToString((ENUM_TIMEFRAMES)Period())` in the auto-magic hash key.
- Use the same timeframe representation in config logs.

## Additional Note: `.set` Compatibility
In the same change set, some inputs were renamed from points-based names to unit-specific names:
- FX: `InpDeviationPoints` → `InpDeviationPips`
- JP225: `InpDeviationPoints` → `InpDeviationYen`
- USIndex: `InpDeviationPoints` → `InpDeviationDollars`

This can cause old `.set` files to load with defaults or mismatched values.
If backward compatibility is required, consider keeping the old input variable names or implementing a compatibility mapping strategy.

## Attachments to Include in the GitHub Issue
- Screenshot or text copy of the MetaEditor compile log (full output)
- The `.mq5` file name(s) that failed
- If applicable, the `.set` file used
