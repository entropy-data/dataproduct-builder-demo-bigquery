# {{DATA_PRODUCT_NAME}}

dbt data product `{{DATA_PRODUCT_ID}}` (dbt project `{{DBT_NAME}}`) on Google BigQuery. Published to [Entropy Data](https://entropy-data.com).

| | BigQuery location (`{{LOCATION}}`) |
|---|---|
| Output port `{{OUTPUT_PORT_ID}}` | `{{PROJECT}}.{{DATASET}}.{{TABLE}}` |
| Staging / intermediate (internal) | `{{PROJECT}}.{{INTERNAL_DATASET}}` |

## Tools

Nothing to install besides [uv](https://docs.astral.sh/uv/): the tools run through `uvx`, pinned to Python 3.12:

```bash
alias dbt='uvx --python 3.12 --from dbt-core --with dbt-bigquery dbt'
alias dbt-ol='uvx --python 3.12 --from openlineage-dbt --with dbt-bigquery dbt-ol'
alias datacontract="uv tool run --from 'datacontract-cli[bigquery]' datacontract"
uv tool install entropy-data
```

## Configure

dbt uses the project-local `profiles.yml` (gitignored, created from `profiles.yml.example`, no secrets). Always pass `--profiles-dir .`:

```bash
cp -n profiles.yml.example profiles.yml
```

**dbt writes**: it creates the datasets `{{DATASET}}` and `{{INTERNAL_DATASET}}` in `{{PROJECT}}` (location `{{LOCATION}}`) and the tables and views in them, and reads the input-port datasets. The identity needs BigQuery Job User and BigQuery Data Editor (or `bigquery.datasets.create`) in `{{PROJECT}}`, and BigQuery Data Viewer on the input ports.

```bash
# target dev (default): your own Google login
gcloud auth application-default login

# target prod (CI): a writer service account
# export BIGQUERY_KEYFILE=/path/to/writer-key.json
```

**`datacontract test` only reads**, so a read-only service account is enough: BigQuery Job User, BigQuery Data Viewer on `{{DATASET}}`, and BigQuery Read Session User (the CLI reads through the Storage Read API). Without a key it uses your Application Default Credentials:

```bash
# export DATACONTRACT_BIGQUERY_ACCOUNT_INFO_JSON_PATH=/path/to/readonly-key.json
```

Entropy Data API key, for the OpenLineage transport and for resolving semantic references in `datacontract lint`:

```bash
export ENTROPY_DATA_API_KEY=<your-entropy-data-api-key>
export OPENLINEAGE__TRANSPORT__AUTH__APIKEY=${ENTROPY_DATA_API_KEY}
export OPENLINEAGE_NAMESPACE=bigquery
```

## Run

```bash
dbt-ol run --profiles-dir .    # runs dbt and ships OpenLineage to Entropy Data
dbt test --profiles-dir .
datacontract test models/output_ports/v1/{{CONTRACT_FILE}} --server {{CONTRACT_SERVER}} --logs
```

## Layout

```
macros/generate_schema_name.sql  # use +schema / config(schema=...) literally as the BigQuery dataset
models/
├── input_ports/      # upstream data products: sources at <project>.<upstream dataset>.<table>
├── staging/          # 1:1 cleaned views over input ports      -> {{INTERNAL_DATASET}}
├── intermediate/     # joined / shaped views                   -> {{INTERNAL_DATASET}}
└── output_ports/v1/  # published tables, one dataset per output port, ODCS contract alongside
```

## Publishing

CI in `.github/workflows/data-product.yml` runs `dbt-ol run` / `dbt test` as a writer service account (target `prod`), publishes `{{ODPS_FILE}}` + the ODCS to Entropy Data, and runs the data contract test against server `{{CONTRACT_SERVER}}`. CI publishes the local `{{ODPS_FILE}}`, so keep it in sync with Entropy Data (`entropy-data dataproducts get {{DATA_PRODUCT_ID}} -o yaml > {{ODPS_FILE}}`), otherwise CI overwrites metadata edited in the web UI.
