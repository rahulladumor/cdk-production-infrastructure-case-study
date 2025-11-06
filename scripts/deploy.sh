#!/bin/bash
set -e

echo "🚀 Deploying CDK Infrastructure"
echo "===================================="

# Setup Python environment
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install -r requirements.txt

# Deploy
echo "🚀 Deploying infrastructure..."
cdk deploy --all --require-approval never

echo ""
echo "✅ Deployment complete!"
