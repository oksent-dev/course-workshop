# syntax=docker/dockerfile:1

FROM node:24.11.1-bookworm-slim AS node
FROM ruby:4.0.9-slim-bookworm AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libvips postgresql-client && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && bundle exec bootsnap precompile --gemfile

COPY package.json package-lock.json .npmrc ./
RUN npm ci --include=dev

COPY . .

RUN chmod +x bin/* && \
    bundle exec bootsnap precompile app/ lib/

RUN SECRET_KEY_BASE_DUMMY=1 NODE_ENV=production SKIP_YARN_INSTALL=1 \
    ruby bin/rails assets:precompile

RUN rm -rf node_modules

FROM base AS final

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails

ENV HOME=/home/rails
USER rails:rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["ruby", "bin/rails", "server", "-b", "0.0.0.0"]
