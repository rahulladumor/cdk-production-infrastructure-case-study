#!/bin/bash
source .venv/bin/activate
echo "🔍 Validating CDK code..."
cdk synth
echo "✅ Validation complete"
