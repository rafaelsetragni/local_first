# Dart WebSocket Server Dockerfile
FROM dart:stable

# Install necessary tools
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Expose WebSocket port
EXPOSE 8080

# Note: The actual code will be mounted as a volume
# Dependencies will be installed when the container starts
CMD ["sh", "-c", "cd /app/local_first_websocket && dart pub get && dart run example/server/websocket_server.dart"]
