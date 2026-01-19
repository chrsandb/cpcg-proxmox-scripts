#!/usr/bin/env bash
# Test script to demonstrate progress indicators

# Source the common library
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Initialize progress tracking for 5 steps
init_progress 5

# Step 1
progress_step "Authenticating to API"
progress_substep "Connecting to server..."
sleep 1
progress_substep "Validating credentials..."
sleep 1
progress_substep "Authentication successful"

# Step 2
progress_step "Downloading data"
progress_substep "Fetching file list..."
sleep 1
progress_substep "Downloading files..."
sleep 1
progress_substep "Download complete"

# Step 3
progress_step "Processing data"
progress_substep "Parsing configuration..."
sleep 1
progress_substep "Validating data..."
sleep 1
progress_substep "Processing complete"

# Step 4
progress_step "Deploying changes"
progress_substep "Creating resources..."
sleep 1
progress_substep "Configuring settings..."
sleep 1
progress_substep "Resources deployed"

# Step 5
progress_step "Finalizing"
progress_substep "Running cleanup..."
sleep 1
progress_substep "Verifying installation..."
sleep 1
progress_substep "All checks passed"

# Completion
progress_complete "Operation completed successfully!"
