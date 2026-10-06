FROM ruby:4.0.7-slim AS base

WORKDIR /app

FROM base AS build

RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    build-essential \
    libssl-dev \
    pkg-config \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

RUN bundle config set without test \
  && bundle install

FROM build AS test

COPY . ./

RUN bundle config unset without \
  && bundle install \
  && bundle exec rspec

FROM base AS runtime

RUN apt-get update \
  && apt-get install --no-install-recommends -y \
    ca-certificates \
    libssl3 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --shell /usr/sbin/nologin app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . ./

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=test \
    RACK_ENV=production

USER app

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:8080/healthz")).is_a?(Net::HTTPSuccess) ? 0 : 1)'

CMD ["bin/start"]
