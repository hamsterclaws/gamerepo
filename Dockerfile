FROM debian:bookworm

# LÖVE + OpenGL (Mesa) + audio libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    love \
    libgl1 \
    libgl1-mesa-dri \
    libglu1-mesa \
    libasound2 \
    libpulse0 \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

CMD ["love", "."]
