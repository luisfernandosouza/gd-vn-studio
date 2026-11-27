# Runner de CI do projeto: Ubuntu 24.04 (igual ao ubuntu-24.04 hospedado), um contêiner novo por job.
# As dependências pesadas já vêm instaladas aqui para os jobs não baixarem tudo a cada execução.
FROM myoung34/github-runner:ubuntu-noble

USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential pkg-config curl unzip xvfb ffmpeg \
      libwebkit2gtk-4.1-dev libgtk-3-dev librsvg2-dev libayatana-appindicator3-dev \
 && rm -rf /var/lib/apt/lists/*
