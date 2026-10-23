# Copilot instructions: dataproduct-builder-demo-bigquery

This repository is a coding-agent plugin that helps build **Google BigQuery** dbt data products and integrate them with [Entropy Data](https://entropy-data.com). It is the BigQuery sibling of [dataproduct-builder-demo](https://github.com/entropy-data/dataproduct-builder-demo) (Snowflake) and [dataproduct-builder-demo-databricks](https://github.com/entropy-data/dataproduct-builder-demo-databricks) (Databricks), and a streamlined demo derivative of [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt).

Capabilities are exposed as **skills**: markdown files under `skills/<name>/SKILL.md` that the agent reads top-to-bottom and executes step by step.

## Routing

When a user request matches a skill's trigger, **read the corresponding `SKILL.md` start to finish before acting.**

| When the user asks about… | Follow this skill |
|---|---|
| Scaffolding a brand-new BigQuery dbt data product from scratch | `skills/dataproduct-bootstrap/SKILL.md` |
| Implementing a data product from a published Entropy Data URL or id, running dbt + OpenLineage + dbt tests + data contract tests | `skills/dataproduct-implement/SKILL.md` |
| Testing existing data contracts against the live BigQuery data | `skills/datacontract-test/SKILL.md` |

The trigger phrasing above is illustrative; each `SKILL.md`'s frontmatter `description` is authoritative.

## Resolving `${PLUGIN_ROOT}`

Skill files reference `${PLUGIN_ROOT}` to locate the templates under `skills/dataproduct-bootstrap/templates/`. On Claude Code it is set automatically as `${CLAUDE_PLUGIN_ROOT}`. On Copilot / Codex / Cursor, it is **not** set: resolve it as the directory containing `AGENTS.md` and `skills/`.

## CLIs the skills shell out to

- **`entropy-data`**: fetch and publish data products / contracts.
- **`dbt`** (`dbt-bigquery` adapter): `uvx --python 3.12 --from dbt-core --with dbt-bigquery dbt … --profiles-dir .`.
- **`dbt-ol`** (`openlineage-dbt`): `uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery dbt-ol … --profiles-dir .`; lineage ships to Entropy Data on the spot (dataset namespace `bigquery`).
- **`datacontract`** (`datacontract-cli[bigquery]`): `uv tool run --from 'datacontract-cli[bigquery]' datacontract`; runs contract tests against BigQuery.

Only `uv` needs to be installed. If it is missing, surface the install line and stop. The Entropy Data API key comes from `ENTROPY_DATA_API_KEY`, else `entropy-data connection get --show-api-key -o json | jq -r .api_key`; never print it.

## Conventions

- **BigQuery only.** If the project's dbt profile (project-local `profiles.yml`) is not `type: bigquery`, stop and point them at https://github.com/entropy-data/dataproduct-builder-demo (Snowflake), https://github.com/entropy-data/dataproduct-builder-demo-databricks (Databricks), or https://github.com/entropy-data/dataproduct-builder-dbt (multi-platform).
- **BigQuery naming.** One dataset per output port named after the output-port / contract id with an optional prefix from the published contract (`customers_v1`), table = contract id without `_v<N>` (`customers`), staging/intermediate in `<prefix><dbt_name>_internal` (`dbt_name` = the kebab-case data product id in snake_case; Entropy Data calls use the original id).
- **Published metadata wins.** Reuse a published data product / contract instead of asking or writing stubs; `# dataproduct-builder:stub` files are replaced without asking.
- **Writer vs. reader.** dbt needs write rights; `datacontract test` is fine with a read-only service account.
- **Don't skip pre-checks.** Both skills verify CLI presence and Entropy Data connection first.
- **Don't overwrite existing files silently.** Surface the diff and ask.
- **Don't run `git init`, commit, or push.** Leave VCS state to the user (list the commands as next steps for them).
- **Don't commit secrets.** API keys and service account keys must come from env vars, key file paths outside the repo, or repo secrets.
- **Idempotent re-runs**, except `dbt run` / `dbt test` / `datacontract test` which always execute.
