---
name: datacontract-test
description: Run `datacontract test` against ODCS contracts in the project to verify the live Google BigQuery data still conforms to schema, quality rules, and freshness. Handles two kinds of contracts with different semantics: output-port contracts under `models/output_ports/**/*.odcs.yaml` (tested against this project's output-port dataset: "am I still producing what I promised?") and input-port contracts under `models/input_ports/*.odcs.yaml` (tested against the upstream data product's dataset: "is upstream still producing what I trusted?"). Trigger when the user asks to "test the data contracts", "verify the data product matches its contract", "are we still contract-conformant", "check upstream drift", or "run the contract tests".
---

# Test ODCS data contracts against BigQuery

Run the **Data Contract CLI** (`datacontract test`) against contracts in the project to check whether the data currently in BigQuery still matches the schema and quality rules declared in the contract.

Two kinds of contracts live in this project and they test against different BigQuery datasets:

- **Output-port contracts** at `models/output_ports/v<N>/*.odcs.yaml`: what this data product commits to produce. They test against **this project's** output-port dataset (`<project>.<dataset>`). A failure means we are no longer producing what we promised.
- **Input-port contracts** at `models/input_ports/*.odcs.yaml`: cached snapshots of what we trust upstream to produce. They test against the **upstream provider's** server (`<project>.<upstream dataset>`), using the server block from the upstream ODCS. A failure means upstream drifted from the contract we trusted; the consequence is that our output may break too. Treat input-port failures as an upstream incident, not a local bug.

## When to use this vs. other skills

- **Just ran `dataproduct-implement` and want to re-test without re-running dbt** → this skill.
- **A CI run failed the contract test step** → this skill, to reproduce locally with `--logs`.
- **You want to edit a contract and check the impact** → not in this demo plugin; use [datacontract-edit](https://github.com/entropy-data/dataproduct-builder-dbt/blob/main/skills/datacontract-edit/SKILL.md) from the full builder.

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin, the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

**Tool invocation.** Below, `datacontract` means `uv tool run --from 'datacontract-cli[bigquery]' datacontract` (a `datacontract` already on PATH works too).

### Plan announcement (before Step 0)

Before running Step 0, print this plan to the user verbatim:

> Running **datacontract-test**. I'll:
> 1. Pre-checks: confirm `datacontract` runs and Google credentials are available.
> 2. Pick which contract(s) to test: defaults to all `models/output_ports/**/*.odcs.yaml` and `models/input_ports/*.odcs.yaml`.
> 3. Pick the server (defaults to the contract's BigQuery server with environment `prod` / `production`).
> 4. Run `datacontract test` per contract and capture the result.
> 5. Report pass/fail with per-rule detail; flag missing credentials separately from real failures.

Then proceed.

### Step 0: Pre-checks

- Confirm `uv tool run --from 'datacontract-cli[bigquery]' datacontract --version` works. If `uv` is missing, stop and tell the user to install it (`curl -LsSf https://astral.sh/uv/install.sh | sh`).
- Confirm at least one `*.odcs.yaml` exists under `models/output_ports/**/` or `models/input_ports/`. If not, stop and tell the user there is nothing to test.
- Confirm Google credentials for the Data Contract CLI. The CLI reads `DATACONTRACT_BIGQUERY_*` env vars, **not** the dbt profile:

  ```bash
  DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON_PATH   # optional: JSON key of a service account
  ```

  Without it, the CLI uses Application Default Credentials: treat BigQuery as ready when either the variable is set or `gcloud auth application-default print-access-token >/dev/null` succeeds. `datacontract test` only runs queries, so a **read-only** identity is enough: BigQuery Job User (to run queries), BigQuery Data Viewer on the datasets under test, and BigQuery Read Session User (the CLI reads columns through the Storage Read API). If neither works, surface what is missing and ask whether to continue or stop. Do not try to source credentials yourself, and never print key contents.

### Step 1: Select contracts

- If the user named a specific contract file or data product id, resolve it to one file. Search both `models/output_ports/**/*.odcs.yaml` and `models/input_ports/*.odcs.yaml`.
- If the user said "output contracts" / "input contracts" / "upstream drift", scope to one of those globs.
- If they did not, default to **all** ODCS files under both globs. List them, grouped by **Output ports** and **Input ports** so the user sees the two roles, then ask before running.
- Remember the resolved list as `CONTRACTS`. For each entry, also remember its role (`output` or `input`): Step 4 surfaces failures differently.

### Step 2: Select the server

For each contract in `CONTRACTS`:

- If the contract has exactly one server, use it.
- If it has multiple, default to the `type: bigquery` server with `environment` `prod` / `production`, then one named `prod` / `production`. Use its actual `.server` name (e.g. `bigquery-prod`), never assume `production`. If none matches, ask the user which one.
- Only pass `--server all` if the user explicitly asks to test every server.
- If the chosen server is not `type: bigquery`, mark the contract `skipped` (this plugin is BigQuery-only).

### Step 3: Run the test

For each contract:

```
uv tool run --from 'datacontract-cli[bigquery]' datacontract test <path-to-contract>.odcs.yaml --server <server> --logs
```

Where `<path-to-contract>` is the file resolved in Step 1, typically `models/output_ports/v<N>/<file>.odcs.yaml` for output contracts, or `models/input_ports/<file>.odcs.yaml` for input contracts. The CLI does not care which directory; the role only matters for how Step 4 reports the result.

- `--logs` ensures per-rule failure detail is in stdout: without it the CLI only prints a summary.
- If the user asks for a persisted report (e.g. to attach to a PR), add `--output ./test-results/<contract>.xml --output-format junit`.
- If the user asks to publish results back to Entropy Data (matches the generated CI workflow), add `--publish <API_HOST>/api/test-results` (`API_HOST` = `entropy-data connection get -o json | jq -r .host`) with `ENTROPY_DATA_API_KEY` set inline, e.g. `ENTROPY_DATA_API_KEY="${ENTROPY_DATA_API_KEY:-$(entropy-data connection get --show-api-key -o json | jq -r .api_key)}"`. `--publish-test-results` is deprecated: don't use it. Do not publish by default: it writes server-side state.
- Capture stdout and exit code per contract. Non-zero exit means at least one rule failed.

Run sequentially, not in parallel: parallel runs muddy the log output.

### Step 4: Report

End with this two-part recap. Use the `Status` enum: `passed`, `failed`, `skipped` (missing creds or non-BigQuery server).

**Part 1: outcome table.** One row per contract tested. Group the rows: output-port contracts first, then input-port contracts under a sub-header (so the reader sees the two roles at a glance).

| Contract | Role | Server | Result | Failures | Details |
|---|---|---|---|---|---|
| `<contract-file>` | `output` / `input` | `<server>` (`<project>.<dataset>`) | `passed` / `failed` / `skipped` | count or `-` | one line per failing rule (field + rule), or "missing credentials: …" if skipped |

**Part 2: next steps.** Bullet list, include only what applies. Treat output vs. input failures differently:

- **Output-port failures**: surface the field and the violated check (e.g. `customers.customer_id: not_null violated for 17 rows`). The fix is in this project: either the dbt model is wrong, the contract is wrong, or the data is wrong. If the user wants a follow-up SQL to find the offending rows, suggest the shape but do not run it.
- **Input-port failures**: this is upstream drift. Name the provider data product and output port (from the contract id and file name). The fix is *not* in this project: the user should contact the upstream owner, and in the meantime expect downstream output-port failures. Suggest re-running `dataproduct-implement` once upstream republishes a corrected contract, so the cached snapshot under `models/input_ports/` refreshes.
- For each `skipped` row, what the user needs to set up (`gcloud auth application-default login`, or `DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON_PATH` with a read-only key).
- **Not data failures**, but setup:
  - `Access Denied` / `403` on an input port usually means the access agreement isn't provisioned as a BigQuery grant yet (BigQuery Data Viewer on the upstream dataset), not drift.
  - `bigquery.readsessions.create` denied: the identity lacks BigQuery Read Session User.
  - `Table "<t>" must be qualified with a dataset`: a `quality` SQL names the table without its dataset. Qualify it in the contract as `<dataset>.<table>`.
- If failures look like a data quality issue (rules unchanged, data drifted), suggest investigating the upstream of the failing model: this skill does not auto-fix data.

If everything passed, write a single line: `All <N> contracts pass against <server>.`

## BigQuery authentication

The Data Contract CLI reads credentials from the environment, not from the contract file. Only the connection topology belongs in the `servers` block, always with an explicit `project`:

```yaml
servers:
  - server: bigquery-prod           # the name is free-form; pass it to --server
    type: bigquery
    environment: prod
    project: acme-data-prod
    dataset: customers_v1
    customProperties:
      - property: location          # informational; BigQuery finds the dataset's location itself
        value: EU
```

There is no `table` in the server block: the table is the contract's `schema[].physicalName // name` (e.g. `customers`). Quality SQL must name it with its dataset (`customers_v1.customers`).

**Application Default Credentials** (local runs, Workload Identity Federation in CI): no env vars needed.

```bash
gcloud auth application-default login
```

**Service account key** (read-only service account):

```bash
export DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON_PATH=/secrets/datacontract-reader.json
```

Grant the service account BigQuery Job User and BigQuery Read Session User in the project that runs the queries, and BigQuery Data Viewer on the datasets under test, nothing more. This read-only identity is enough for contract tests; dbt runs need a separate identity with write rights (see `dataproduct-implement`).

Optional: `DATACONTRACT_BIGQUERY_IMPERSONATION_ACCOUNT` to impersonate a service account, and `DATACONTRACT_BIGQUERY_BILLING_PROJECT` to run the queries in another project than the data.

## Constraints

- **Read-only against BigQuery.** This skill runs `datacontract test` which executes `SELECT` queries; it never writes. Do not invoke `datacontract publish`, `datacontract export`, or `entropy-data datacontracts put` from this skill.
- **No edits to contracts or models.** If a test fails, surface it: do not auto-patch the contract to make it pass. That defeats the purpose.
- **No credential sourcing.** If credentials are missing, tell the user; don't read them from `.env`, dotfiles, or anywhere else on the user's behalf.
- **Idempotent**: re-running the skill produces the same report against the same data. Failures from rules that depend on time (freshness, row-count windows) are expected to drift: note that in the failure detail when relevant.
