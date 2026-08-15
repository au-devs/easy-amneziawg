FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends openssh-client ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# docker CLI only -- the daemon is the host's, reached through the mounted socket
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ARG HTMX_VERSION=2.0.4
RUN mkdir -p app/static && \
    curl -fsSL "https://unpkg.com/htmx.org@${HTMX_VERSION}/dist/htmx.min.js" \
      -o app/static/htmx.min.js

COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
