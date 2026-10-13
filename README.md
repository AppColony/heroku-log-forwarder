# Heroku Log Forwarder

A small Heroku application that receives runtime-metrics lines from Heroku Logplex and re-emits them as JSON logs to New Relic.

## Why it exists

New Relic's Heroku syslog parser expects an `app[heroku-*]` Logplex prefix. Heroku's `log-runtime-metrics` feature writes `heroku[<dyno>]: ... sample#<key>=<value>` lines instead, which New Relic drops. A source-app buildpack cannot intercept these lines because Heroku writes them directly to Logplex rather than dyno stdout.

## Architecture

```text
source-app dynos
  |
  | Heroku Logplex fan-out
  +-- existing drain --> New Relic
  |
  +-- HTTPS drain --> /newrelic/<source-app>
                         |
                         v
                  Sinatra + Logplex frame parser
                         |
                         v
                 local Fluentd Forward input
                         |
                         v
                 New Relic Log API JSON ingest
```

Heroku posts `application/logplex-1` octet-counted syslog batches. The Sinatra endpoint unwraps those batches, keeps runtime-metrics messages, and sends flat numeric metric attributes to Fluentd. Fluentd buffers and forwards them to New Relic.

## Record schema

Each forwarded New Relic record contains:

| Attribute | Value |
| --- | --- |
| `timestamp` | Epoch milliseconds, converted from the syslog frame timestamp. Omitted when the frame timestamp is unparseable; the New Relic plugin then stamps its ingest time. |
| `source` | Source app name from the drain URL path. |
| `dyno_source` | Dyno name from the syslog procid (for example `web.1`). |
| `logtype` | `heroku.runtime_metrics` for dyno metrics, `heroku.addon_metrics` for add-on metrics. |
| `makeshift_app` | Dashboard contract attribute, resolved from the drain route. |
| `makeshift_environment` | Dashboard contract attribute, resolved from the drain route. |
| metric fields | One field per `sample#key=value` token, unit-suffixed where present (`memory_total_mb`). |

The New Relic output plugin authenticates with the `NR_API_KEY` environment variable, which must contain a New Relic license key (sent as `X-License-Key`).

## Environment metadata

The dashboard filters on two server-controlled attributes emitted with every record:

```text
makeshift_app            e.g. makesh-staging (the drain route's source segment)
makeshift_environment    e.g. staging
```

Built-in route mapping lives in `lib/log_forwarder/metadata.rb`:

| Drain route | `makeshift_app` | `makeshift_environment` |
| --- | --- | --- |
| `/newrelic/makeshift-staging` | `makeshift-staging` | `staging` |
| `/newrelic/makeshift-prod` | `makeshift-prod` | `production` |

Additional routes can be added without a deploy via the `MAKESHIFT_ROUTE_METADATA` environment variable (comma-separated `app:environment` pairs, no secrets allowed in it). Enrichment is merged into each record last, so a payload can never override the contract attributes. Unknown routes are rejected with `404` and forwarded nowhere — traffic is never silently labeled with a guessed environment.

Dashboard verification (New Relic):

```sql
SELECT count(*) FROM Log
WHERE logtype = 'heroku.runtime_metrics'
FACET makeshift_app, makeshift_environment SINCE 30 minutes ago
```

## Wire format

Heroku HTTPS drains deliver RFC5424-style frames where the timestamp, app name, and procid are envelope fields, and the message body carries only runtime metrics:

```text
146 <40>1 2026-10-08T13:41:00.443714+00:00 host heroku sidekiq.1 - source=sidekiq.1 dyno=heroku.x sample#load_avg_1m=0.00 sample#memory_total=459.95MB
```

The `heroku[<dyno>]:` prefix seen in `heroku logs` CLI output is a render of the envelope; it is not part of the delivered message. Lines from non-`heroku` apps are ignored.

## Deploy

```bash
git clone https://github.com/AppColony/heroku-log-forwarder.git
cd heroku-log-forwarder
bundle install

# The Heroku app itself is provisioned by AppColony/gitops. Do not recreate it.
heroku git:remote -a makeshift-log-forwarder-staging
heroku config:set NR_API_KEY=<NR_INSIGHTS_INSERT_KEY> -a makeshift-log-forwarder-staging
heroku config:set RACK_ENV=production -a makeshift-log-forwarder-staging
git push heroku main

curl https://makeshift-log-forwarder-staging.herokuapp.com/healthz
```

`NR_API_KEY` must be a New Relic Insights Insert Key. The Fluentd New Relic plugin sends it as `X-Insert-Key`.

`AppColony/gitops` owns the existing staging app's Heroku configuration:
application shell, Ruby buildpack, `standard-1x` web formation, and MakeShift
staging pipeline coupling. This repository owns the application source; deploy
new source revisions manually with `git push heroku main`. `NR_API_KEY` remains
an operator-managed Heroku config var and is never stored in Terraform.

## CI/CD

Merging a pull request into `main` runs `.github/workflows/test.yml`. The test
jobs gate two approval-gated deploy jobs:

```text
ruby + container (tests)
  └─ deploy-staging        (environment: staging, manual approval)
       └─ deploy-production  (environment: production, manual approval)
```

Each deploy job pushes the merged `main` revision to the target Heroku app over
HTTPS and finishes with a `GET /healthz` smoke check, retried for up to 30
seconds to absorb dyno restarts during release. Deploys run only on merges to
`main` or manual `workflow_dispatch` replays — pull request runs deploy nothing.

`deploy-staging` targets `log-forwarder-staging`. `deploy-production` reads its
app name from the `PROD_APP_NAME` repository variable and skips until that
variable is set; the production forwarder is provisioned by `AppColony/gitops`.

Approval gates, the `main`-only deployment branch rule, and environment-scoped
secrets are configured in repo Settings → Environments (`staging`,
`production`):

| Name | Scope | Value |
| --- | --- | --- |
| `HEROKU_API_TOKEN` | both `staging` and `production` environments | Heroku deploy token for a CI account with access to the target apps |
| `HEROKU_EMAIL` | both `staging` and `production` environments | Email of that CI Heroku account |
| `PROD_APP_NAME` | repository variable | Production forwarder app name, set after gitops provisions it |

## Wire A Source App

Add a second HTTPS drain in the source app's `gitops` workspace:

```text
https://<forwarder>.herokuapp.com/newrelic/<source-app-name>
```

For example:

```text
https://makeshift-log-forwarder-staging.herokuapp.com/newrelic/makeshift-staging
```

The path segment becomes `source`. The runtime dyno from the log line becomes `dyno_source`. This one forwarder serves multiple source apps through distinct paths.

## Environment

| Variable | Purpose |
| --- | --- |
| `NR_API_KEY` | Required New Relic Insights Insert Key. |
| `PORT` | Web port assigned by Heroku, default `8080`. |
| `RACK_ENV` | Set to `production` on Heroku. |

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `POST /newrelic/:source` | Receives Heroku HTTPS-drain batches. Returns an empty `200` response. |
| `GET /healthz` | Returns `OK`. |

## Development

Ruby `4.0.7` is required. Dependencies are intentionally unpinned in `Gemfile`; commit the generated `Gemfile.lock` after dependency changes.

```bash
bundle install
bundle exec rspec
bash bin/test

NR_API_KEY=test bin/start
curl http://localhost:8080/healthz
```

The RSpec suite stubs Fluentd, so it does not require Heroku or a New Relic key. Validate the Fluentd configuration with:

```bash
NR_API_KEY=test bundle exec fluentd --dry-run -c config/fluentd.conf
```

## Container

Build the production image or run its test stage:

```bash
docker build -t heroku-log-forwarder .
docker build --target test .
docker run --rm -p 8080:8080 -e NR_API_KEY=test heroku-log-forwarder
```

Test the Fluent Bit-to-Fluentd Forward-protocol connection without calling New Relic:

```bash
docker compose up --build --abort-on-container-exit --exit-code-from verify
docker compose down --volumes
```

The Compose stack starts this app with `config/fluentd.compose.conf`, sends a synthetic `fluentbit.connectivity` event from Fluent Bit, and waits until Fluentd writes that event to a shared volume.

## Limitations

- This is a workaround for a New Relic and Heroku prefix mismatch. Remove it if New Relic supports `heroku[<dyno>]` runtime-metrics lines natively.
- Only Heroku runtime-metrics lines are forwarded. Other logs continue to use the existing New Relic drain.
- HTTPS drains are unauthenticated by design. Do not expose this route as a general-purpose trusted ingestion API.
- This app is stateless and has no database.

## References

- [Heroku HTTPS drains](https://devcenter.heroku.com/articles/log-drains#https-drains)
- [New Relic Fluentd output](https://github.com/newrelic/newrelic-fluentd-output)
- `AppColony/gitops` plan section 22
