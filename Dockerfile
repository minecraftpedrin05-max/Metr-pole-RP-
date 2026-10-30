# Servidor do RP Game para o Railway (ou qualquer lugar que rode Docker).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 libgl1 libasound2 \
    && rm -rf /var/lib/apt/lists/*

# baixa o Godot (versao sem tela, so o executavel)
RUN curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . /app

# Os arquivos podem ter sido enviados soltos (sem a pasta "sistema"): arruma aqui.
RUN mkdir -p /app/sistema \
    && for f in rede servidor itens catalogo config_cidade personagens; do \
         if [ -f "/app/$f.gd" ]; then mv "/app/$f.gd" "/app/sistema/$f.gd"; fi; \
       done \
    && ls -R /app

RUN godot --headless --path /app --import || true

# Dados salvos (contas, carros, casas) ficam em /data. No Railway, crie um Volume montado em /data.
ENV XDG_DATA_HOME=/data
RUN mkdir -p /data

CMD ["godot", "--headless", "--path", "/app"]
