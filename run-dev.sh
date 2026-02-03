#!/bin/bash
# Development runner - loads env vars and runs the app

set -e

# Load environment variables
if [ -f .env.local ]; then
    echo "Loading environment variables from .env.local..."
    source .env.local
else
    echo "Warning: .env.local not found"
fi

# Run the app
cd ActivityBarApp
swift run ActivityBarApp
