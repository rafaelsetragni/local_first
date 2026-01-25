#!/bin/bash

# WebSocket Server Docker Runner with Hot Reload
# This script builds and runs the WebSocket server in a Docker container
# with volume mounting for automatic code updates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CONTAINER_NAME="local_first_websocket_server"
IMAGE_NAME="local_first_websocket_server:dev"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Local First WebSocket Server${NC}"
echo "======================================"

# Check if MongoDB is accessible on port 27017
if lsof -Pi :27017 -sTCP:LISTEN -t >/dev/null 2>&1 || nc -z localhost 27017 >/dev/null 2>&1; then
    echo -e "${GREEN}MongoDB is already running on port 27017${NC}"
else
    # Check if mongo_local container exists but is stopped
    if docker ps -a --format '{{.Names}}' | grep -q '^mongo_local$'; then
        echo "Starting existing MongoDB container..."
        docker start mongo_local
        echo -e "${GREEN}MongoDB container started${NC}"
        sleep 3
    else
        # Create and start new MongoDB container
        echo "Creating MongoDB container..."
        docker run -d --name mongo_local -p 27017:27017 \
            -e MONGO_INITDB_ROOT_USERNAME=admin \
            -e MONGO_INITDB_ROOT_PASSWORD=admin \
            mongo:7
        echo -e "${GREEN}MongoDB started${NC}"
        sleep 3
    fi
fi

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Build the Docker image
echo "Building Docker image..."
cd "$PROJECT_ROOT"
docker build -f local_first_websocket/example/server/Dockerfile -t "$IMAGE_NAME" .

# Run the container with volume mounting for hot reload
echo "Starting WebSocket server container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --network host \
    -v "$PROJECT_ROOT:/app" \
    -w /app \
    "$IMAGE_NAME"

echo -e "${GREEN}WebSocket server started!${NC}"
echo ""
echo "Server URL: ws://localhost:8080"
echo "Container name: $CONTAINER_NAME"
echo ""
echo "Commands:"
echo "  View logs:    docker logs -f $CONTAINER_NAME"
echo "  Stop server:  docker stop $CONTAINER_NAME"
echo "  Remove:       docker rm $CONTAINER_NAME"
echo ""
echo "Note: Files are mounted from your local directory."
echo "Code changes will require container restart to take effect."

# Show initial logs
echo ""
echo "Server logs:"
docker logs -f "$CONTAINER_NAME"
