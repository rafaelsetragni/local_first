#!/bin/bash

# Script to install all example apps to a selected device
# This script allows interactive device selection when multiple devices are available

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Install Local First Example Apps     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Get list of devices and parse them
echo -e "${YELLOW}Detecting available devices...${NC}"
echo ""

# Get devices in a parseable format
DEVICE_LIST=$(flutter devices --machine 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$DEVICE_LIST" ]; then
  echo -e "${RED}Error: Could not detect devices${NC}"
  exit 1
fi

# Parse device list using jq or basic parsing
# Extract device names and IDs
DEVICE_NAMES=()
DEVICE_IDS=()

# Simple parsing without jq dependency
while IFS= read -r line; do
  if [[ $line =~ \"name\":\ *\"([^\"]+)\" ]]; then
    name="${BASH_REMATCH[1]}"
  fi
  if [[ $line =~ \"id\":\ *\"([^\"]+)\" ]]; then
    id="${BASH_REMATCH[1]}"
    DEVICE_NAMES+=("$name")
    DEVICE_IDS+=("$id")
  fi
done <<< "$DEVICE_LIST"

# Check if we found any devices
if [ ${#DEVICE_IDS[@]} -eq 0 ]; then
  echo -e "${RED}No devices found!${NC}"
  echo ""
  echo "Run 'flutter devices' to check available devices"
  exit 1
fi

# Show device selection menu
echo -e "${GREEN}Available devices:${NC}"
echo ""

for i in "${!DEVICE_NAMES[@]}"; do
  num=$((i + 1))
  echo -e "${YELLOW}${num})${NC} ${DEVICE_NAMES[$i]}"
done

echo ""

# Check if device number was provided as argument
if [ -n "$1" ]; then
  DEVICE_NUM="$1"
  echo -e "${BLUE}Using device number from argument: ${DEVICE_NUM}${NC}"
else
  echo -e "${YELLOW}Enter device number (1-${#DEVICE_IDS[@]}):${NC}"
  read -r DEVICE_NUM
fi

# Validate input
if ! [[ "$DEVICE_NUM" =~ ^[0-9]+$ ]] || [ "$DEVICE_NUM" -lt 1 ] || [ "$DEVICE_NUM" -gt "${#DEVICE_IDS[@]}" ]; then
  echo -e "${RED}Invalid selection!${NC}"
  exit 1
fi

# Get selected device (adjust for 0-based array)
SELECTED_INDEX=$((DEVICE_NUM - 1))
DEVICE_ID="${DEVICE_IDS[$SELECTED_INDEX]}"
DEVICE_NAME="${DEVICE_NAMES[$SELECTED_INDEX]}"

echo ""
echo -e "${GREEN}✓ Selected: ${DEVICE_NAME}${NC}"
echo -e "${BLUE}  Device ID: ${DEVICE_ID}${NC}"
echo ""

# List of example directories
EXAMPLES=(
  "local_first/example"
  "local_first_hive_storage/example"
  "local_first_sqlite_storage/example"
  "local_first_shared_preferences/example"
  "local_first_websocket/example"
  "local_first_periodic_strategy/example"
)

FAILED=0
SUCCEEDED=0

echo -e "${BLUE}Installing examples...${NC}"
echo ""

for example in "${EXAMPLES[@]}"; do
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Installing: ${example}${NC}"
  echo ""

  # Change to example directory
  pushd "$example" > /dev/null || {
    echo -e "${RED}✗ Failed to access directory: ${example}${NC}"
    ((FAILED++))
    continue
  }

  # Run flutter install with verbose output
  if flutter install -d "$DEVICE_ID" -v; then
    echo ""
    echo -e "${GREEN}✓ Success: ${example}${NC}"
    ((SUCCEEDED++))
  else
    echo ""
    echo -e "${RED}✗ Failed: ${example}${NC}"
    ((FAILED++))
  fi

  # Return to original directory
  popd > /dev/null
  echo ""
done

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Installation Summary         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo -e "${GREEN}Succeeded: ${SUCCEEDED}${NC}"
if [ $FAILED -gt 0 ]; then
  echo -e "${RED}Failed: ${FAILED}${NC}"
else
  echo -e "${YELLOW}Failed: ${FAILED}${NC}"
fi
echo ""
