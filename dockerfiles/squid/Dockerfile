FROM ghcr.io/alphagov/verify/alpine:3.11

RUN apk add --no-cache squid=4.13-r0

RUN    touch /etc/squid/squid.conf \
    && mkdir -p /squid \
    && chown -R squid /etc/squid/squid.conf /squid

EXPOSE 8080

WORKDIR /tmp

USER squid

COPY ./docker-entrypoint.sh /tmp/docker-entrypoint.sh

ENTRYPOINT ["/tmp/docker-entrypoint.sh"]
