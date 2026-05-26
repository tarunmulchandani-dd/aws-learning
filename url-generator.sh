#!/bin/bash

# ── Read from env if not passed ───────────────────────────────────────────────
DEFAULT_REGION=${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}
DEFAULT_STAGE=${AWS_STAGE:-"prod"}

# ── Prompts ───────────────────────────────────────────────────────────────────
read -p "Lambda function name : " FUNCTION_NAME
read -p "API Gateway name     : " API_NAME
read -p "Stage     [$DEFAULT_STAGE]   : " STAGE
read -p "Region    [$DEFAULT_REGION]  : " REGION
read -p "Method    [POST]             : " METHOD
read -p "Path      [/upload]          : " API_PATH

# ── Apply defaults for anything left blank ────────────────────────────────────
STAGE=${STAGE:-$DEFAULT_STAGE}
REGION=${REGION:-$DEFAULT_REGION}
METHOD=${METHOD:-"POST"}
API_PATH=${API_PATH:-"/upload"}
METHOD=${METHOD^^}   # uppercase

# ── Resolve API ID ────────────────────────────────────────────────────────────
API_ID=$(aws apigateway get-rest-apis \
  --region "$REGION" \
  --query "items[?name=='$API_NAME'].id" \
  --output text 2>/dev/null)

if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  echo "Error: API '$API_NAME' not found in region '$REGION'."
  exit 1
fi

# ── Print URL ─────────────────────────────────────────────────────────────────
URL="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE$API_PATH"

echo ""
echo "  $METHOD $URL"
echo ""
