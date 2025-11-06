#!/bin/bash
source .venv/bin/activate
echo "🗑️  Destroying infrastructure..."
cdk destroy --all --force
echo "✅ Cleanup complete"
