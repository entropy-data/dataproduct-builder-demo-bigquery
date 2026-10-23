---
name: dataproduct-bootstrap
description: Bootstrap a brand-new Google BigQuery dbt data product from scratch in one go (dbt_project.yml, generate_schema_name macro, model layout, README, .gitignore, profiles.yml(.example) for BigQuery, ODPS, output-port ODCS, openlineage.yml, and a GitHub Actions workflow). Reuses the data product and contract when they are already published on Entropy Data. Trigger when the user asks to start a new data product, scaffold a new dbt project, or "create a BigQuery data product from scratch."
---

# Bootstrap a new BigQuery dbt data product (demo)

Scaffold a BigQuery-only dbt data product following the Entropy Data conventions and the BigQuery naming convention below. Demo-grade: one batched question, one platform, no audits, no migration logic.

If the data product is **already published** on Entropy Data (the usual demo flow: the product and its contract were designed in the web UI first), this skill takes name, purpose, team, output ports, and the output-port contract from there, including project, dataset and location from the contract's BigQuery server. It then asks nothing at all, or only for what Entropy Data cannot know.

For populating the contract schema and dbt model bodies from a published data product, use the **dataproduct-implement** skill after this one.

## BigQuery naming convention

| Object | Convention | Example |
|---|---|---|
| Project | the organization's GCP project | `acme-data-prod` |
| Output-port dataset | `<DATASET_PREFIX>` + the output-port id = the contract id (ends in `_v<N>`). The prefix is optional and usually empty. | `customers_v1`, or `acme_customers_v1` with prefix `acme_` |
| Output-port table | the contract id without the `_v<N>` suffix | `customers` |
| Internal dataset | `<DATASET_PREFIX><DBT_NAME>_internal`: staging + intermediate, never granted to consumers | `customers_internal` |
| Input ports | `<project>.<upstream dataset>.<table>` as dbt sources | `acme-data-prod.orders_v2.orders` |
| Location | the location of the datasets, from the contract server's `customProperties` `location` | `EU`, `europe-west3` |

`macros/generate_schema_name.sql` makes dbt take `+schema` / `config(schema=...)` literally as the dataset name, so the output-port model lands in `customers_v1` rather than `<target_dataset>_customers_v1`. In dbt-bigquery, `database` is the GCP project and `schema` is the dataset.

## What this skill produces

After running, the directory contains:

```
.
├── dbt_project.yml
├── .gitignore
├── .dbtignore
├── README.md
├── profiles.yml.example
├── profiles.yml                  (gitignored, no secrets)
├── <data-product-id>.odps.yaml
├── openlineage.yml
├── .github/workflows/data-product.yml
├── macros/generate_schema_name.sql
└── models/
    ├── input_ports/_models.yml
    ├── staging/_models.yml
    ├── intermediate/_models.yml
    └── output_ports/v1/
        ├── _models.yml
        └── <contract-id>.odcs.yaml
```

## How to run this skill

> `${PLUGIN_ROOT}` below refers to the root of this plugin, the directory that contains `skills/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`; use that. On any other agent (Codex, Copilot CLI, etc.) it is unset; resolve it as `../..` relative to **this `SKILL.md` file's directory** (i.e. the grandparent of `skills/<this-skill>/`).

### Plan announcement (before Step 1)

Before running Step 1, print this plan to the user verbatim:

> Running **dataproduct-bootstrap**. I'll:
> 1. Pre-check: confirm the working directory is empty and the `entropy-data` CLI is connected.
> 2. Look the data product up on Entropy Data; if it is published, reuse its name, purpose, team, output port, and data contract (with the BigQuery project, dataset, and location).
> 3. Ask you for the remaining parameters in one batched question, only what Entropy Data doesn't already know.
> 4. Scaffold the dbt project (dbt_project.yml, generate_schema_name macro, profiles.yml + profiles.yml.example, model layout, README, .gitignore).
> 5. Scaffold the publishing layer (ODPS, output-port ODCS: the published ones when they exist, openlineage.yml, GitHub Actions workflow).
> 6. Summarize what was scaffolded and the next manual steps.

Then proceed.

### Step 1: Pre-checks

- Confirm the working directory is empty, or contains only files the user is fine with (e.g. an empty git repo, a `LICENSE`, or a placeholder `README.md` that will be overwritten).
- If `dbt_project.yml` already exists, stop and tell the user this demo skill only handles greenfield directories. Point them at `dataproduct-implement` to add models to an existing project.
- Confirm `entropy-data connection test` succeeds and resolve `API_HOST` = `${ENTROPY_DATA_HOST}` if set (it overrides the stored connection, like `ENTROPY_DATA_API_KEY`), else `entropy-data connection get -o json | jq -r .host` (no trailing `/`). If the CLI is not connected, stop and tell the user to run `entropy-data connection add <name> --host <host> --api-key <key>` first. The demo does not run without a working connection.

Always use the `entropy-data` CLI for any connection to Entropy Data. Do not use the Entropy Data MCP server.

### Step 2: Reuse what is already published

If the user's request names a data product (id or URL `https://<app>/<org>/dataproducts/<id>`, take the trailing id), run `entropy-data dataproducts get <id> -o yaml`. Entropy Data ids are usually kebab-case (`regional-score-statistics`); use the id **exactly as published** for every Entropy Data call. If the request names none, skip to Step 3 and repeat this lookup with the id the user answers.

If the lookup succeeds, remember the YAML as `PUBLISHED_ODPS` and take:

- `DATA_PRODUCT_NAME` = `.name`, `PURPOSE` = `.description.purpose`, `TEAM_NAME` = `.team.name // .team.id`.
- The output port: the first entry of `.outputPorts` with `type: bigquery` (else the first one). `OUTPUT_PORT_ID` = its `.id // .name`, `CONTRACT_ID` = its `.contractId`. If there are several output ports, scaffold the first and tell the user `dataproduct-implement` handles the others.

If `CONTRACT_ID` is set, run `entropy-data datacontracts get <CONTRACT_ID> -o yaml`. If that succeeds, remember it as `PUBLISHED_CONTRACT` and take from its BigQuery server (`servers[]` with `type: bigquery`; prefer `environment` `prod` / `production`, then server name `prod` / `production`, then the first one):

- `CONTRACT_SERVER` = `.server`, `PROJECT` = `.project`, `DATASET` = `.dataset`, and `LOCATION` from a `customProperties` entry `location` if present.
- `TABLE` = `schema[0].physicalName // schema[0].name`.

Anything published wins over defaults; do not ask for it again.

### Step 3: Gather the missing parameters in one batched question

Ask the user, in a single prompt, for **only the parameters not resolved in Step 2** (with a published data product and a contract with a complete BigQuery server, that is typically nothing). Do not generate any files until you have all of them. Pre-fill `PROJECT` / `LOCATION` as suggested defaults when `BIGQUERY_PROJECT` / `BIGQUERY_LOCATION` (or `GOOGLE_CLOUD_PROJECT`) are set in the shell, and `DATASET_PREFIX` from `BIGQUERY_DATASET_PREFIX`. If everything is already known, skip the question and state the values you will use.

| Parameter | Description | Example |
|---|---|---|
| `DATA_PRODUCT_ID` | Entropy Data id, kebab-case or snake_case | `customers` / `regional-score-statistics` |
| `DATA_PRODUCT_NAME` | Human-friendly name | `Customers` |
| `PURPOSE` | One sentence: why this data product exists | `Customer master data for customer success.` |
| `TEAM_NAME` | Owning team id (free-text accepted for the demo) | `customer-success` |
| `PROJECT` | GCP project of the datasets | `acme-data-prod` |
| `OUTPUT_PORT_ID` | First output port id = contract id. snake_case, must end in `_v1` | `customers_v1` |
| `DATASET_PREFIX` | Optional prefix of every dataset of this data product, usually empty | `acme_` |
| `LOCATION` | BigQuery location of the datasets | `EU` / `europe-west3` |

If the user supplied `DATA_PRODUCT_ID` only now, run the Step 2 lookup with it; if it is published, the published values replace the answers (say so) and the contract is fetched as in Step 2.

Validate: `DATA_PRODUCT_ID` must match `^[a-z][a-z0-9_-]*$`; `OUTPUT_PORT_ID` and `DATASET_PREFIX` must match `^[a-z0-9_]*$` (BigQuery dataset names: letters, digits, underscores); `PROJECT` must match `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`; a new `OUTPUT_PORT_ID` must match `_v1$` (published ones are taken as they are). If a value is invalid, ask again for that value only.

Derive (unless resolved in Step 2):

- `DBT_NAME` = `DATA_PRODUCT_ID` lower-cased with every character outside `[a-z0-9_]` replaced by `_` (e.g. `regional-score-statistics` → `regional_score_statistics`). Used as dbt project name and dbt profile name: dbt and BigQuery need snake_case; Entropy Data keeps the original id.
- `CONTRACT_ID` = `OUTPUT_PORT_ID` (e.g. `customers_v1`)
- `DATASET` = `<DATASET_PREFIX><OUTPUT_PORT_ID>` (the output-port dataset)
- `DATASET_PREFIX`, when `DATASET` came from the published contract: the part of `DATASET` before `OUTPUT_PORT_ID` if `DATASET` ends with `OUTPUT_PORT_ID` (e.g. `ing_customers_v1` → `ing_`), else empty.
- `TABLE` = `OUTPUT_PORT_ID` with the trailing `_v<N>` removed (e.g. `customers`)
- `CONTRACT_SERVER` = `production` (the server name in the stub contract)
- `INTERNAL_DATASET` = `<DATASET_PREFIX><DBT_NAME>_internal`. The prefix keeps every dataset of the data product under one naming rule, so whoever cleans up by prefix also finds the internal one.
- `CONTRACT_FILE` = `<CONTRACT_ID>.odcs.yaml`
- `CONTRACT_PATH` = `models/output_ports/v1/<CONTRACT_FILE>`
- `ODPS_FILE` = `<DATA_PRODUCT_ID>.odps.yaml`

### Step 4: Scaffold the project

Templates live under `${PLUGIN_ROOT}/skills/dataproduct-bootstrap/templates/`. Copy each one into the working directory, substituting placeholders.

**Placeholder rule:** substitute only `{{UPPER_SNAKE_CASE}}` tokens (e.g. `{{PROJECT}}`). Values such as `PURPOSE` contain colons, quotes, and dashes, so substitute with a small script (e.g. Python `re.sub(r"\{\{([A-Z_]+)\}\}", …)` over a dict of the values), not `sed`, and check afterwards that no `{{UPPER_SNAKE_CASE}}` token is left (`grep -rE '\{\{[A-Z_]+\}\}'`). Leave dbt Jinja such as `{{ env_var('BIGQUERY_KEYFILE') }}` / `{{ config(...) }}` and GitHub Actions expressions such as `${{ secrets.X }}` untouched.

| Template | Destination |
|---|---|
| `dbt_project.yml` | `dbt_project.yml` |
| `.gitignore` | `.gitignore` |
| `.dbtignore` | `.dbtignore` (keeps dbt from parsing `*.odcs.yaml` as schema files) |
| `README.md` | `README.md` |
| `profiles.yml.example` | `profiles.yml.example` **and** `profiles.yml` (same content: no secrets; gitignored) |
| `macros/generate_schema_name.sql` | `macros/generate_schema_name.sql` |
| `data-product.odps.yaml` | `<ODPS_FILE>`, **only if not published.** If `PUBLISHED_ODPS` exists, write it verbatim instead: `entropy-data dataproducts get <DATA_PRODUCT_ID> -o yaml > <ODPS_FILE>` (CI's `dataproducts put` publishes this file, so a stub would overwrite the richer published product) |
| `openlineage.yml` | `openlineage.yml` |
| `models/input_ports/_models.yml` | `models/input_ports/_models.yml` |
| `models/staging/_models.yml` | `models/staging/_models.yml` |
| `models/intermediate/_models.yml` | `models/intermediate/_models.yml` |
| `models/output_ports/v1/_models.yml` | `models/output_ports/v1/_models.yml` |
| `models/output_ports/v1/contract.odcs.yaml` | `<CONTRACT_PATH>`, **only if not published.** If `PUBLISHED_CONTRACT` exists, write it verbatim instead: `entropy-data datacontracts get <CONTRACT_ID> -o yaml > <CONTRACT_PATH>` (no stub that `dataproduct-implement` would have to overwrite) |
| `.github/workflows/data-product.yml` | `.github/workflows/data-product.yml` |

Create each destination directory first (`mkdir -p`), including `models/output_ports/v1/` before the `datacontracts get … >` redirect. Also create empty `analyses/`, `seeds/`, `snapshots/`, `tests/` directories with a `.gitkeep` each (`macros/` already has the schema macro).

The stub templates start with a `# dataproduct-builder:stub` comment. Keep it in stub files (`dataproduct-implement` replaces marked files without asking) and never add it to files written from Entropy Data.

All dbt commands in this project run with `--profiles-dir .` so the project-local `profiles.yml` is used, never `~/.dbt/profiles.yml`.

### Step 5: Final report

End with this two-part recap. Use the `Status` enum: `created`, `already present`, `skipped`.

**Part 1: outcome table.**

| Artifact | Status | Details |
|---|---|---|
| `dbt_project.yml` | … | project / profile = `<DBT_NAME>`, BigQuery adapter |
| `macros/generate_schema_name.sql` | … | literal datasets |
| `profiles.yml` / `profiles.yml.example` | … | BigQuery, project `<PROJECT>`, location `<LOCATION>`, your gcloud login (`dev`) or a writer key file (`prod`); `profiles.yml` gitignored |
| `README.md` | … | written |
| `.gitignore` / `.dbtignore` | … | written |
| Model layout | … | `models/{input_ports,staging,intermediate,output_ports/v1}/` |
| ODPS | … | `<ODPS_FILE>`: "from Entropy Data" / "stub" |
| Output-port contract | … | `<CONTRACT_PATH>` → `<PROJECT>.<DATASET>.<TABLE>`, server `<CONTRACT_SERVER>`: "from Entropy Data" / "stub (`id` + `updated_at`)" |
| `openlineage.yml` | … | transport pointed at `<API_HOST>` |
| GitHub Actions workflow | … | `.github/workflows/data-product.yml` |

**Part 2: next steps.** Bullet list:

- Tools run via uv, nothing to install into the project: `uvx --python 3.12 --from dbt-core --with dbt-bigquery dbt`, `uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery dbt-ol`, `uv tool run --from 'datacontract-cli[bigquery]' datacontract` (see the README's aliases).
- Google credentials: `gcloud auth application-default login` for target `dev` (default), or `BIGQUERY_KEYFILE` with the JSON key of a writer service account for target `prod`.
- **dbt writes, `datacontract test` only reads.** The identity running dbt needs BigQuery Job User and BigQuery Data Editor (or `bigquery.datasets.create`) in `<PROJECT>`, so that it can create `<DATASET>` and `<INTERNAL_DATASET>`, and BigQuery Data Viewer on the input-port datasets. A read-only service account with BigQuery Job User, BigQuery Data Viewer and BigQuery Read Session User is enough for `datacontract test`.
- `export ENTROPY_DATA_API_KEY=<your-entropy-data-api-key>`: `dataproduct-implement` uses it for the OpenLineage transport, and the contract lint hook needs it to resolve semantic references.
- For you to run (the agent leaves version control to you): `git init && git add . && git commit -m "Initial commit"`, then push to GitHub.
- Set GitHub repository secrets for the workflow: `ENTROPY_DATA_API_KEY` and `GCP_SA_KEY` (the JSON key of a writer service account; or switch the workflow to Workload Identity Federation).
- Run **dataproduct-implement** next to generate models from the published data product, run dbt, run dbt + datacontract tests, and ship the first lineage event.

## Constraints

- **BigQuery-only.** This demo plugin intentionally drops platform branching. If the user asks for Snowflake, point them at https://github.com/entropy-data/dataproduct-builder-demo; for Databricks, at https://github.com/entropy-data/dataproduct-builder-demo-databricks; for multi-platform projects, at the full builder at https://github.com/entropy-data/dataproduct-builder-dbt.
- **Greenfield only.** If `dbt_project.yml` exists, stop.
- **Do not run `dbt init`.** Use the templates here.
- **Do not commit secrets.** `profiles.yml` is in `.gitignore` and, like `profiles.yml.example`, holds no credentials: the `dev` target uses your gcloud login, the `prod` target reads the key file path from `BIGQUERY_KEYFILE`. Never print API keys, tokens, or key file contents.
- **Published metadata wins.** Never write a stub ODPS or contract when Entropy Data already has the real one.
- **Do not run `git init`, `git commit`, or `git push`**: list them as next steps for the user.
- **Idempotent.** Re-running on an already-populated directory is a no-op (refuse if anything would be overwritten).
