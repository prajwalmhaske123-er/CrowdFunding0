#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  # Export variables ignoring comments
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found."
  echo "Please create a .env file with RPC_URL and PRIVATE_KEY."
  exit 1
fi

# Check if required variables are set
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set in .env"
  exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY is not set in .env"
  exit 1
fi

echo "Deploying CrowdFunding contract..."

# Run the forge deployment script
# PRIVATE_KEY is read from the environment automatically by Foundry
# (avoids exposing the key in process listings / shell history)
forge script deploy_script/deploy.s.sol:DeployCrowdFunding \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv

if [ $? -eq 0 ]; then
    echo "Deployment successful!"
else
    echo "Deployment failed."
    exit 1
fi
