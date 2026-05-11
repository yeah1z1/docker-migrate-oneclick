FROM alpine:3.20

LABEL org.opencontainers.image.title="Docker迁移一键通"
LABEL org.opencontainers.image.description="可视化选择 Docker 容器并一键生成迁移包"
LABEL org.opencontainers.image.source="https://github.com/yeah1z1/docker-migrate-oneclick"
LABEL org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache \
    bash \
    coreutils \
    curl \
    docker-cli \
    findutils \
    gawk \
    gzip \
    iproute2 \
    jq \
    sed \
    tar \
    python3

COPY docker-migrate.sh /usr/local/bin/docker-migrate-cn

RUN chmod +x /usr/local/bin/docker-migrate-cn \
    && mkdir -p /tmp/docker-migrate-cn

ENV WEB_PORT=5555 \
    PORT=8088 \
    WORK_ROOT=/tmp/docker-migrate-cn \
    HELPER_IMAGE=alpine:3.20

EXPOSE 5555
VOLUME ["/tmp/docker-migrate-cn"]

ENTRYPOINT ["docker-migrate-cn"]
CMD ["--web"]
