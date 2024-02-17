FROM ruby:3.2-alpine3.18 AS build

RUN addgroup -S -g 1000 manyfold && adduser -S -H -G manyfold -u 1000 manyfold

RUN apk add --no-cache \
            coreutils \
            tzdata \
            alpine-sdk \
            postgresql-dev \
            nodejs \
            yarn \
            xz \
            libarchive \
            mesa-gl \
            glfw \
            bash \
            su-exec \
            tini \
            wget

# (bundler needs this for running as an arbitrary user)
ENV HOME /home/manyfold
RUN [ ! -d "$HOME" ]; \
    mkdir -p "$HOME"; \
    chown manyfold:manyfold "$HOME"; \
    chmod 1777 "$HOME"

ARG APP_VERSION
ARG GIT_SHA

ENV PORT=3214
ENV RACK_ENV=production
ENV RAILS_ENV=production
ENV NODE_ENV=production
ENV RAILS_SERVE_STATIC_FILES=true
ENV APP_VERSION=${APP_VERSION}
ENV GIT_SHA=${GIT_SHA}
WORKDIR /usr/src/app

RUN wget -O manyfold.tar.gz https://github.com/manyfold3d/manyfold/archive/refs/tags/${APP_VERSION}.tar.gz; \
    tar -xf manyfold.tar.gz --strip-components=1; \
    rm manyfold.tar.gz; \
    mkdir -p log public/plugin_assets sqlite; \
    chown -R manyfold:manyfold ./; \
	  echo 'config.logger = Logger.new(STDOUT)' > config/additional_environment.rb; \
    # fix permissions for running as an arbitrary user
	  chmod -R ugo=rwX config db sqlite; \
	  find log tmp -type d -exec chmod 1777 '{}' +

RUN yarn config set network-timeout 600000 -g
RUN yarn install --prod

RUN su-exec manyfold gem install foreman
RUN su-exec manyfold gem install bundler -v 2.4.13
RUN bundle config set --local deployment 'true'
RUN bundle config set --local without 'development test'
RUN chmod -R ugo=rwX Gemfile.lock "$GEM_HOME";
# this requires coreutils because "chmod +X" in busybox will remove +x on files (and coreutils leaves files alone with +X)
RUN rm -rf ~manyfold/.bundle

RUN echo '# the following entries only exist to force `bundle install` to pre-install all database adapter dependencies -- they can be safely removed/ignored' > ./config/database.yml; \
    for adapter in mysql2 postgresql sqlserver sqlite3; do \
      echo "$adapter:" >> ./config/database.yml; \
      echo "  adapter: $adapter" >> ./config/database.yml; \
    done; \
    su-exec manyfold bundle install --jobs "$(nproc)"; \
    rm ./config/database.yml;

# RUN runDeps="$( \
# 		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/bundle/gems \
# 		| tr ',' '\n' \
# 		| sort -u \
# 		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
#     )"; \
#     apk add --no-network --virtual .manyfold-rundeps $runDeps;

RUN ls -al
EXPOSE 3214

COPY docker-entrypoint.sh bin/docker-entrypoint.sh
ENTRYPOINT ["bin/docker-entrypoint.sh"]

CMD ["foreman", "start"]
