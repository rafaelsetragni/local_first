#!/bin/bash

# WebSocket Server Docker Compose Runner
# This script manages the full stack (MongoDB + WebSocket Server) using docker-compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Local First WebSocket Server Stack    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    echo "Please install Docker Desktop which includes Docker Compose"
    exit 1
fi

# Use docker compose (new) or docker-compose (old)
COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
fi

cd "$SCRIPT_DIR"

# Check for existing containers and clean them up
if docker ps -a --format '{{.Names}}' | grep -q "^local_first_websocket_server$\|^local_first_mongodb$"; then
    echo -e "${YELLOW}Cleaning up existing containers...${NC}"
    docker stop local_first_websocket_server local_first_mongodb 2>/dev/null || true
    docker rm local_first_websocket_server local_first_mongodb 2>/dev/null || true
    echo ""
fi

echo -e "${BLUE}Starting services...${NC}"
echo ""

# Start services in detached mode
$COMPOSE_CMD up -d --remove-orphans

echo ""
echo -e "${GREEN}✓ Services started successfully!${NC}"
echo ""
echo -e "${YELLOW}Service URLs:${NC}"
echo "  MongoDB:         mongodb://admin:admin@localhost:27017"
echo "  WebSocket Server: ws://localhost:8080"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  View logs:        $COMPOSE_CMD logs -f websocket_server"
echo "  View all logs:    $COMPOSE_CMD logs -f"
echo "  Stop services:    $COMPOSE_CMD stop"
echo "  Restart services: $COMPOSE_CMD restart"
echo "  Stop & remove:    $COMPOSE_CMD down"
echo "  Stop & clean all: $COMPOSE_CMD down -v"
echo ""
echo -e "${BLUE}Following server logs (Ctrl+C to exit):${NC}"
echo ""

# Follow logs
$COMPOSE_CMD logs -f websocket_server
