# Agent Guide

## Layout

- `app.rb`: Sinatra HTTP endpoints only.
- `lib/log_forwarder/logplex.rb`: Logplex octet-frame and syslog-envelope parsing.
- `lib/log_forwarder/runtime_metrics.rb`: runtime-metrics record generation.
- `config/fluentd.conf`: local Forward input and New Relic output.
- `spec/`: RSpec unit and request coverage.

## Constraints

- The source-app buildpack at `https://github.com/AppColony/buildpack-runtime-metrics-json.git#v0.1.1` cannot intercept Heroku-emitted Logplex lines. This app is its architectural complement, not a buildpack.
- `AppColony/gitops` owns the staging Heroku app at `projects/platform/heroku-us/makeshift-log-forwarder-staging/`, including its app shell, Ruby buildpack, web formation, and pipeline coupling. Operators own source code, secrets, and deployment with `git push heroku main`.
- Keep the drain path exactly `/newrelic/<source-app-name>`. The source path is required for multi-app attribution.
- One forwarder serves all MakeShift applications. Do not create one forwarder per source app.
- Keep the current stack: Heroku-24, Ruby 4.0.7, Sinatra, Fluentd. Consult the platform team before changing it.
- Preserve the NR record schema: `timestamp` (epoch ms integer), `source`, `dyno_source`, and `logtype` are dashboard attributes.
- Heroku HTTPS drains deliver syslog frames with timestamp/app/procid in the envelope and metrics-only message bodies. Parsers must accept the wire format; the rendered `heroku[dyno]:` CLI shape is a compat case only.
- Do not add a database or user authentication. Heroku drains are unauthenticated.

## Common Changes

- New Logplex framing behavior: update `lib/log_forwarder/logplex.rb` and its unit specs.
- New runtime-metrics format or field: update `lib/log_forwarder/runtime_metrics.rb` and its unit specs.
- New HTTP endpoint: update `app.rb` and `spec/app_spec.rb`.
- New New Relic transport behavior: update `config/fluentd.conf` and validate it with Fluentd dry-run.

## Verification

```bash
bundle install
bundle exec rspec
bash bin/test
NR_API_KEY=test bundle exec fluentd --dry-run -c config/fluentd.conf
bundle exec fluentd --dry-run -c config/fluentd.compose.conf
docker build --target test .
docker compose up --build --abort-on-container-exit --exit-code-from verify
docker compose down --volumes
```
