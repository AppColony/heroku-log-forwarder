# Agent Guide

## Layout

- `app.rb`: Sinatra HTTP endpoints only.
- `lib/log_forwarder/logplex.rb`: Logplex octet-frame and syslog-envelope parsing.
- `lib/log_forwarder/runtime_metrics.rb`: runtime-metrics record generation.
- `config/fluentd.conf`: local Forward input and New Relic output.
- `spec/`: RSpec unit and request coverage.

## Constraints

- The source-app buildpack at `https://github.com/AppColony/buildpack-runtime-metrics-json.git#v0.1.1` cannot intercept Heroku-emitted Logplex lines. This app is its architectural complement, not a buildpack.
- This app has no `AppColony/gitops` workspace. Gitops only owns adding the second drain; operators own this app through the Heroku CLI.
- Keep the drain path exactly `/newrelic/<source-app-name>`. The source path is required for multi-app attribution.
- One forwarder serves all MakeShift applications. Do not create one forwarder per source app.
- Keep the current stack: Heroku-24, Ruby 4.0.7, Sinatra, Fluentd. Consult the platform team before changing it.
- Preserve the NR record schema: `timestamp`, `source`, `dyno_source`, and `logtype` are dashboard attributes.
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
```
