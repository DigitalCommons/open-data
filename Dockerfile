# Cloudron app image: the admin Rails app plus the converter projects.
# Build and deploy: see "Cloudron deployment" in admin/README.md.
FROM cloudron/base:5.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        libyaml-dev libsqlite3-dev gosu rsync openssl git \
    && rm -rf /var/lib/apt/lists/*

# Ruby via mise, pinned by mise.toml. /usr/local/ruby is a stable path so
# runtime scripts don't need mise or the version number.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh
ENV MISE_DATA_DIR=/usr/local/mise
WORKDIR /app/code
COPY mise.toml ./
RUN mise trust mise.toml && mise install && ln -s "$(mise where ruby)" /usr/local/ruby
ENV PATH=/usr/local/ruby/bin:$PATH

# Admin app gems
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test
COPY admin/Gemfile admin/Gemfile.lock admin/.ruby-version admin/
RUN cd admin && bundle install --jobs 4

COPY . .

RUN cd admin && SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production bundle exec rails assets:precompile

# Only /app/data, /run and /tmp are writable at runtime
RUN cd admin && rm -rf tmp log storage \
    && ln -s /run/app/tmp tmp \
    && ln -s /run/app/log log \
    && ln -s /app/data/storage storage

ENV RAILS_ENV=production \
    SOLID_QUEUE_IN_PUMA=1 \
    OPEN_DATA_ROOT=/app/data/open-data \
    DOWNLOADS_ROOT=/app/data/downloads \
    PORT=3000

CMD ["/app/code/start.sh"]
