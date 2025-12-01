#!/bin/bash
# =============================================================================
# Scratch Org Setup Script for WSM-Tools-JSON-to-Records
# =============================================================================
# This script creates a new scratch org, pushes the source, and runs tests.
#
# Prerequisites:
#   - Salesforce CLI installed (sf or sfdx)
#   - Authenticated to a DevHub org
#
# Usage:
#   ./scripts/scratch-org-setup.sh [org-alias]
#
# Example:
#   ./scripts/scratch-org-setup.sh json-records-dev
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default org alias
ORG_ALIAS="${1:-json-to-records-scratch}"
SCRATCH_ORG_DURATION=7

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  WSM-Tools-JSON-to-Records - Scratch Org Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if Salesforce CLI is installed
if ! command -v sf &> /dev/null; then
    echo -e "${RED}ERROR: Salesforce CLI (sf) not found. Please install it first.${NC}"
    echo "  npm install -g @salesforce/cli"
    exit 1
fi

# Check for DevHub authorization
echo -e "${YELLOW}Checking DevHub authorization...${NC}"
if ! sf org list --json 2>/dev/null | grep -q '"isDevHub": true'; then
    echo -e "${RED}ERROR: No DevHub org authorized. Please authorize a DevHub first:${NC}"
    echo "  sf org login web --set-default-dev-hub --alias DevHub"
    exit 1
fi
echo -e "${GREEN}✓ DevHub authorized${NC}"

# Create scratch org
echo ""
echo -e "${YELLOW}Creating scratch org '${ORG_ALIAS}'...${NC}"
sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "$ORG_ALIAS" \
    --duration-days "$SCRATCH_ORG_DURATION" \
    --set-default \
    --wait 10

echo -e "${GREEN}✓ Scratch org created${NC}"

# Push source
echo ""
echo -e "${YELLOW}Pushing source to scratch org...${NC}"
sf project deploy start --target-org "$ORG_ALIAS"
echo -e "${GREEN}✓ Source pushed${NC}"

# Run tests
echo ""
echo -e "${YELLOW}Running Apex tests...${NC}"
sf apex run test \
    --target-org "$ORG_ALIAS" \
    --code-coverage \
    --result-format human \
    --wait 10

# Get org info
echo ""
echo -e "${YELLOW}Scratch org details:${NC}"
sf org display --target-org "$ORG_ALIAS"

# Open the org
echo ""
echo -e "${YELLOW}Opening scratch org in browser...${NC}"
sf org open --target-org "$ORG_ALIAS"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Useful commands:"
echo "  sf org open --target-org $ORG_ALIAS     # Open the org"
echo "  sf project deploy start                  # Push changes"
echo "  sf apex run test --code-coverage        # Run tests"
echo "  sf org delete scratch -o $ORG_ALIAS     # Delete the scratch org"
echo ""
