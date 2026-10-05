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

## Deploy

```bash
git clone https://github.com/AppColony/heroku-log-forwarder.git
cd heroku-log-forwarder
bundle install

heroku create makeshift-log-forwarder-staging --region us --remote log-forwarder
heroku config:set NR_API_KEY=<NR_INSIGHTS_INSERT_KEY> -a makeshift-log-forwarder-staging
heroku config:set RACK_ENV=production -a makeshift-log-forwarder-staging
git push log-forwarder main

curl https://makeshift-log-forwarder-staging.herokuapp.com/healthz
```

`NR_API_KEY` must be a New Relic Insights Insert Key. The Fluentd New Relic plugin sends it as `X-Insert-Key`.

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

## Limitations

- This is a workaround for a New Relic and Heroku prefix mismatch. Remove it if New Relic supports `heroku[<dyno>]` runtime-metrics lines natively.
- Only Heroku runtime-metrics lines are forwarded. Other logs continue to use the existing New Relic drain.
- HTTPS drains are unauthenticated by design. Do not expose this route as a general-purpose trusted ingestion API.
- This app is stateless and has no database.

## References

- [Heroku HTTPS drains](https://devcenter.heroku.com/articles/log-drains#https-drains)
- [New Relic Fluentd output](https://github.com/newrelic/newrelic-fluentd-output)
- `AppColony/gitops` plan section 22
