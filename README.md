# dataproduct-builder-demo-bigquery

Demo-grade coding-agent plugin for building **Google BigQuery** dbt data products with [Entropy Data](https://entropy-data.com).

This is the BigQuery sibling of the Snowflake demo [dataproduct-builder-demo](https://github.com/entropy-data/dataproduct-builder-demo) and the Databricks demo [dataproduct-builder-demo-databricks](https://github.com/entropy-data/dataproduct-builder-demo-databricks), and a streamlined derivative of the full [dataproduct-builder-dbt](https://github.com/entropy-data/dataproduct-builder-dbt): fewer skills, no platform branching, one batched question, and the implement skill runs dbt + tests + contract tests + OpenLineage on the spot so the data product shows up in Entropy Data in minutes.

## Skills

- **[dataproduct-bootstrap](skills/dataproduct-bootstrap/SKILL.md)** scaffolds a new BigQuery dbt data product from scratch: `dbt_project.yml`, the `generate_schema_name` macro, model layout, README, `profiles.yml` + `profiles.yml.example`, ODPS, output-port ODCS, OpenLineage transport, and a GitHub Actions workflow. If the data product (and its contract) is already published on Entropy Data, it reuses them, including project, dataset, and location from the contract's BigQuery server.
- **[dataproduct-implement](skills/dataproduct-implement/SKILL.md)** fetches a published data product, derives dbt models from its purpose, ODCS contract, and input-port contracts, runs `dbt-ol run` (which ships lineage to Entropy Data immediately), runs `dbt test` and `datacontract test`, and marks the output port active on Entropy Data, end-to-end in one pass.
- **[datacontract-test](skills/datacontract-test/SKILL.md)** runs `datacontract test` against output-port and input-port ODCS files to verify the live BigQuery data still matches the contract.

## Install

The skills are plain markdown; any coding agent that can read instruction files can run them.

### Claude Code

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo-bigquery
/plugin install dataproduct-builder-demo-bigquery@dataproduct-builder-demo-bigquery
```

### OpenAI Codex

```
codex plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo-bigquery
```

Then open Codex, run `/plugins`, and pick `dataproduct-builder-demo-bigquery`.

### GitHub Copilot CLI

```
/plugin marketplace add https://github.com/entropy-data/dataproduct-builder-demo-bigquery
/plugin install dataproduct-builder-demo-bigquery@dataproduct-builder-demo-bigquery
```

### Other agents (Cursor, Aider, etc.)

Any agent that reads `AGENTS.md` picks up the routing manifest. Or copy the `skills/` directory into the path your coding agent expects.

## Connect

Only [uv](https://docs.astral.sh/uv/) is required; the skills run dbt, dbt-ol, and the Data Contract CLI through it, pinned to Python 3.12:

```
uvx --python 3.12 --from dbt-core --with dbt-bigquery dbt …
uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery dbt-ol …
uv tool run --from 'datacontract-cli[bigquery]' datacontract …
```

### Entropy Data

The skills authenticate against Entropy Data through a connection registered with the [entropy-data CLI](https://github.com/entropy-data/entropy-data-cli).

Create a user-scoped key in the Entropy Data web UI (**Organization Settings → API Keys → Create new API key**, scope `User (personal token)`) and add the connection:

```
uv tool install --upgrade entropy-data
entropy-data connection add default --api-key <your-api-key> --host <your-entropy-data-host>
```

Also export the key as `ENTROPY_DATA_API_KEY` (the skills prefer it over the stored connection key). The contract lint hook needs it: contracts that link semantic business definitions are resolved through the Entropy Data API, and without a key the hook can only warn about them. If the semantics IRIs point at a different host than your connection, also set `ENTROPY_DATA_HOST` to that host.

```bash
export ENTROPY_DATA_API_KEY=<your-api-key>
```

### Google BigQuery

Nothing secret is written to a file: the generated project-local `profiles.yml` (gitignored) uses your gcloud login, or reads the path of a key file from `BIGQUERY_KEYFILE`.

**dbt writes**: it creates the output-port and internal datasets, tables, and views, and reads the input ports. It needs BigQuery Job User and BigQuery Data Editor (or `bigquery.datasets.create`) in the project, and BigQuery Data Viewer on the input-port datasets. Either your own login or a writer service account:

```bash
# a) your Google login (Application Default Credentials)    -> dbt target dev
gcloud auth application-default login

# b) writer service account                                 -> dbt target prod
# export BIGQUERY_KEYFILE=/path/to/writer-key.json
```

**`datacontract test` only reads**, so a read-only service account is enough: BigQuery Job User, BigQuery Read Session User (the CLI reads columns through the Storage Read API), and BigQuery Data Viewer on the datasets under test. Without a key it uses your Application Default Credentials:

```bash
# export DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON_PATH=/path/to/readonly-key.json
```

## Use

In an empty directory, ask the agent:

> Bootstrap a BigQuery dbt data product *(optionally: for the data product url or id)*.

Then, once the scaffold is in place:

> Implement the data product *url or id*.

The implement skill runs end-to-end: it generates the models, runs `dbt-ol run` against BigQuery, runs `dbt test`, runs `datacontract test`, and ships the OpenLineage event so the pipeline shows up in Entropy Data right away. The GitHub Actions workflow is written to the repo as a reference for production use.

## BigQuery naming convention

| Object | Convention | Example |
|---|---|---|
| Project | the organization's GCP project | `acme-data-prod` |
| Output-port dataset | an optional prefix + the output-port / contract id, one dataset per output port | `customers_v1` |
| Output-port table | the contract id without the `_v<N>` suffix | `customers` |
| Internal dataset (staging + intermediate) | the same prefix + `<dbt_name>_internal` (data product id in snake_case), never granted to consumers | `regional_score_statistics_internal` |
| Input port (upstream) | `<project>.<upstream dataset>.<table>`, declared as a dbt source | `acme-data-prod.orders_v2.orders` |

The prefix (e.g. `acme_`) is optional and taken from the published contract's dataset. It keeps every dataset of a data product under one naming rule, so a shared project can be cleaned up by prefix.

A `generate_schema_name` macro override makes dbt use `+schema` / `config(schema=...)` literally as the dataset name instead of prefixing the target dataset, so `customers_v1` lands as `customers_v1`, not `customers_internal_customers_v1`.

## BigQuery-only

This demo plugin drops multi-platform branching to keep the flow short. The user is asked one batched question, the templates are BigQuery-shaped (datasets, BigQuery types, `method: oauth` profile), and the runtime invocations target the `dbt-bigquery` adapter and the `datacontract-cli[bigquery]` extras.

- For **Snowflake**, use the sibling demo at https://github.com/entropy-data/dataproduct-builder-demo.
- For **Databricks**, use the sibling demo at https://github.com/entropy-data/dataproduct-builder-demo-databricks.
- For **Postgres** or multi-platform projects, use the full builder at https://github.com/entropy-data/dataproduct-builder-dbt.

All plugins can coexist.

## License

MIT
