FROM mcr.microsoft.com/devcontainers/python:3-3.14-trixie

COPY ./incus.sources /etc/apt/sources.list.d/zabbly-incus-stable.sources

RUN rm /etc/apt/sources.list.d/yarn.list && \
    curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc && \
    apt-get update && \
    apt-get install -y 7zip xorriso incus-client

RUN --mount=type=bind,target=/build/bashrc,src=./bashrc \
    cat /build/bashrc >> /home/vscode/.bashrc
