# syntax=docker/dockerfile:1
# ----------------------------
# Base: MkDocs Material + deps
# ----------------------------
FROM squidfunk/mkdocs-material:latest AS base

COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /docs

# ----------------------------
# Dev: serveur local (livereload)
# ----------------------------
FROM base AS dev

ENTRYPOINT ["/sbin/tini", "--", "mkdocs"]
CMD ["serve", "--dev-addr=0.0.0.0:8000", "--strict", "--livereload"]
# CMD ["serve", "--dev-addr=0.0.0.0:8000", "--livereload"]
EXPOSE 8000


# ----------------------------
# CI: exécution libre (mike, mkdocs build)
# ----------------------------
FROM base AS ci

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-lc", "mkdocs --version && mike --version"]
