# dataproduct-builder-demo-bigquery: agent manifest

> **This file is the plugin's authoritative routing manifest, not a template.** It lives at the plugin's repo root and is meant to be **referenced** from your project (e.g. via Codex CLI's marketplace install, or a one-line pointer in your project's own `AGENTS.md`), not copied into your project. Updating the plugin updates this file in place.

This repository is a coding-agent plugin that helps build **Google BigQuery** dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It is the BigQuery sibling of [dataproduct-builder-demo](https://github.com/entropy-data/dataproduct-builder-demo) (Snowflake) and [dataproduct-builder-demo-databricks](https://github.com/entropy-data/dataproduct-builder-demo-databricks) (Databricks), and a streamlined demo derivative of [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt). It exposes its capabilities as **skills**: markdown files under `skills/<name>/SKILL.md` that you read top-to-bottom and execute step by step.

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.** Each skill contains audit steps, parameter-gathering, and explicit user-confirmation gates that must not be skipped.

## Skills

| When the user asks about… | Follow this skill |
|---|---|
| Scaffolding a brand-new BigQuery dbt data product from scratch (greenfield, empty directory) | `skills/dataproduct-bootstrap/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id, running dbt + OpenLineage + dbt tests + data contract tests end-to-end | `skills/dataproduct-implement/SKILL.md` |
| Testing existing data contracts against the live BigQuery data (no edits, just run `datacontract test`) | `skills/datacontract-test/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative.

## Resolving `${PLUGIN_ROOT}`

The skill files reference `${PLUGIN_ROOT}` to locate the templates under `skills/dataproduct-bootstrap/templates/`. On Claude Code this is set automatically as `${CLAUDE_PLUGIN_ROOT}`; on Codex / Cursor / other agents reading this file, it is **not** set: resolve it as **the directory that contains this `AGENTS.md`** (the cloned repo root, which also contains `skills/`).

## CLIs the skills shell out to

- **`entropy-data`** (PyPI: `entropy-data`; install with `uv tool install entropy-data`): used to fetch data products and contracts, publish updates, list teams. The API key comes from `ENTROPY_DATA_API_KEY` if set, else from the connection (`entropy-data connection get --show-api-key -o json | jq -r .api_key`). Never print it.
- **`dbt`** (`dbt-bigquery` adapter): run as `uvx --python 3.12 --from dbt-core --with dbt-bigquery dbt … --profiles-dir .` (project-local, gitignored `profiles.yml` without credentials).
- **`dbt-ol`** (PyPI: `openlineage-dbt`): run as `uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery dbt-ol … --profiles-dir .`; ships lineage to Entropy Data immediately during implementation. Datasets are emitted under the namespace `bigquery` with names `<project>.<dataset>.<table>`. Don't use `dbt-ol --version` as a pre-check (it crashes without a project or API key); use `uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery python -c "import openlineage.dbt"`.
- **`datacontract`** (PyPI: `datacontract-cli[bigquery]`): run as `uv tool run --from 'datacontract-cli[bigquery]' datacontract`; runs contract tests against the BigQuery server defined in the ODCS file.
- **`gcloud`**: only to check for Application Default Credentials (`gcloud auth application-default print-access-token`). The user logs in themselves.

Only `uv` needs to be installed. If it is missing, surface the install line and stop: do not try to install on the user's behalf without confirmation.

The Claude Code hook `hooks/datacontract_lint.sh` lints edited `*.odcs.yaml` files. Contracts that link semantic business definitions need `ENTROPY_DATA_API_KEY` (and `ENTROPY_DATA_HOST` if the IRIs point at another host) to resolve them; without the key the hook only warns about those references.

## Conventions when running skills

- **BigQuery only.** This demo plugin intentionally drops multi-platform branching. For Snowflake, point users at https://github.com/entropy-data/dataproduct-builder-demo; for Databricks, at https://github.com/entropy-data/dataproduct-builder-demo-databricks; for Postgres, at https://github.com/entropy-data/dataproduct-builder-dbt.
- **BigQuery naming.** Project = the organization's GCP project; one dataset per output port, named after the output-port / contract id with an optional prefix taken from the published contract (e.g. `customers_v1` or `acme_customers_v1`); table = contract id without the `_v<N>` suffix (e.g. `customers`). Staging and intermediate models live in `<prefix><dbt_name>_internal`, where `dbt_name` is the data product id in snake_case (Entropy Data ids are usually kebab-case: `regional-score-statistics` → dbt project/profile `regional_score_statistics`; Entropy Data calls always use the original id). Upstream data products are read as dbt sources from `<project>.<upstream dataset>.<table>`. All datasets of a pipeline must share one location.
- **Don't skip the pre-checks.** Both skills verify CLI presence and Entropy Data connection before touching files.
- **Published metadata wins.** If the data product / contract already exists on Entropy Data, use it instead of asking or writing stubs. Stub files carry a `# dataproduct-builder:stub` marker and are replaced without asking.
- **Writer vs. reader.** dbt needs write rights (BigQuery Job User + BigQuery Data Editor, to create the output-port and internal datasets); `datacontract test` only needs read (BigQuery Job User, BigQuery Data Viewer, BigQuery Read Session User), so a read-only service account is enough there.
- **Don't overwrite existing files silently.** Surface the diff and ask.
- **Don't run `git init`, commit, or push** on the user's behalf: leave VCS state to the user (list the commands as next steps for them).
- **Don't commit secrets.** API keys and service account keys must come from env vars, key file paths outside the repo, or repo secrets.
- **Idempotent re-runs.** Running a skill a second time when everything is already in place should be a no-op, except for `dbt run` / `dbt test` / `datacontract test` which always re-execute by design.
