#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
#  test-lambda.sh — Parameterised Lambda + API Gateway integration tester
#  
#  Usage:
#    ./test-lambda.sh [OPTIONS]
#
#  Options:
#    -n  --name        Lambda function name        (required)
#    -a  --api         API Gateway name            (required)
#    -s  --stage       Stage name                  (default: prod)
#    -r  --region      AWS region                  (default: aws configure get region)
#    -e  --env         Environment local|aws       (default: aws)
#    -m  --method      HTTP method                 (default: POST)
#    -p  --path        API path                    (default: /upload)
#    -f  --file        File to upload              (optional)
#    -d  --data        Extra form fields as k=v    (optional, repeatable)
#    -j  --json        JSON body string            (optional, overrides multipart)
#    -H  --header      Extra headers as k:v        (optional, repeatable)
#    -t  --timeout     Curl timeout in seconds     (default: 30)
#    -v  --verbose     Verbose curl output
#    -l  --logs        Tail Lambda logs after test
#    -h  --help        Show this help
#
#  Examples:
#    # Multipart file upload
#    ./test-lambda.sh -n FileUploadHandler -a FileUploadAPI -f ./test.jpg -d username=john
#
#    # JSON body
#    ./test-lambda.sh -n FileUploadHandler -a FileUploadAPI -j '{"key":"value"}' -m POST -p /data
#
#    # LocalStack
#    ./test-lambda.sh -n FileUploadHandler -a FileUploadAPI -e local -f ./test.jpg
#
#    # Different stage + tail logs
#    ./test-lambda.sh -n FileUploadHandler -a FileUploadAPI -s dev -f ./test.jpg -l
#
#    # GET request
#    ./test-lambda.sh -n FileUploadHandler -a FileUploadAPI -m GET -p /health
# ─────────────────────────────────────────────────────────────────────────────

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"

# ── Defaults ──────────────────────────────────────────────────────────────────
STAGE="prod"
ENV="aws"
METHOD="POST"
API_PATH="/upload"
TIMEOUT=30
VERBOSE=false
TAIL_LOGS=false
EXTRA_FIELDS=()
EXTRA_HEADERS=()
FILE_PATH=""
JSON_BODY=""
FUNCTION_NAME=""
API_NAME=""
REGION=""

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${CYAN}▶ $1${RESET}"; }
ok()      { echo -e "${GREEN}✔ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}"; }
err()     { echo -e "${RED}✘ $1${RESET}"; exit 1; }
info()    { echo -e "${BLUE}  $1${RESET}"; }
divider() { echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ── Help ──────────────────────────────────────────────────────────────────────
show_help() {
  grep "^#  " "$0" | sed 's/^#  //'
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)        FUNCTION_NAME="$2";    shift 2 ;;
    -a|--api)         API_NAME="$2";         shift 2 ;;
    -s|--stage)       STAGE="$2";            shift 2 ;;
    -r|--region)      REGION="$2";           shift 2 ;;
    -e|--env)         ENV="$2";              shift 2 ;;
    -m|--method)      METHOD="${2^^}";       shift 2 ;;
    -p|--path)        API_PATH="$2";         shift 2 ;;
    -f|--file)        FILE_PATH="$2";        shift 2 ;;
    -j|--json)        JSON_BODY="$2";        shift 2 ;;
    -d|--data)        EXTRA_FIELDS+=("$2");  shift 2 ;;
    -H|--header)      EXTRA_HEADERS+=("$2"); shift 2 ;;
    -t|--timeout)     TIMEOUT="$2";          shift 2 ;;
    -v|--verbose)     VERBOSE=true;          shift ;;
    -l|--logs)        TAIL_LOGS=true;        shift ;;
    -h|--help)        show_help ;;
    *) err "Unknown option: $1. Use -h for help." ;;
  esac
done

# ── Validate required args ────────────────────────────────────────────────────
[ -z "$FUNCTION_NAME" ] && err "Lambda function name is required. Use -n <name>"
[ -z "$API_NAME" ]      && err "API Gateway name is required. Use -a <name>"

# ── Resolve region ────────────────────────────────────────────────────────────
if [ -z "$REGION" ]; then
  REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
fi

# ── Set endpoint based on environment ─────────────────────────────────────────
if [ "$ENV" = "local" ]; then
  AWS_ENDPOINT="--endpoint-url http://localhost:4566"
  LOCALSTACK=true
else
  AWS_ENDPOINT=""
  LOCALSTACK=false
fi

AWS_CMD="aws $AWS_ENDPOINT --region $REGION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — Check Lambda
# ─────────────────────────────────────────────────────────────────────────────
divider
echo -e "${BOLD}  SECTION 1 — Lambda Status${RESET}"
divider

log "Checking Lambda: $FUNCTION_NAME"

LAMBDA_INFO=$($AWS_CMD lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --query "{State:State, Runtime:Runtime, Handler:Handler, Modified:LastModified, Memory:MemorySize, Timeout:Timeout}" \
  --output json 2>&1) || err "Lambda function '$FUNCTION_NAME' not found."

LAMBDA_STATE=$(echo "$LAMBDA_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['State'])")

if [ "$LAMBDA_STATE" != "Active" ]; then
  err "Lambda is not Active. Current state: $LAMBDA_STATE"
fi

ok "Lambda is Active"
echo "$LAMBDA_INFO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  Runtime  : {d[\"Runtime\"]}')
print(f'  Handler  : {d[\"Handler\"]}')
print(f'  Memory   : {d[\"Memory\"]} MB')
print(f'  Timeout  : {d[\"Timeout\"]} sec')
print(f'  Modified : {d[\"Modified\"]}')
"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — Resolve API Gateway URL
# ─────────────────────────────────────────────────────────────────────────────
divider
echo -e "${BOLD}  SECTION 2 — API Gateway${RESET}"
divider

log "Looking up API: $API_NAME"

API_ID=$($AWS_CMD apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id" \
  --output text 2>&1) || err "Could not query API Gateway."

[ -z "$API_ID" ] || [ "$API_ID" = "None" ] && err "API '$API_NAME' not found."

ok "Found API ID: $API_ID"

# Verify the stage exists
STAGE_EXISTS=$($AWS_CMD apigateway get-stages \
  --rest-api-id "$API_ID" \
  --query "item[?stageName=='$STAGE'].stageName" \
  --output text)

[ -z "$STAGE_EXISTS" ] && err "Stage '$STAGE' not found for API '$API_NAME'."
ok "Stage '$STAGE' is live"

# Construct the invoke URL
if [ "$LOCALSTACK" = true ]; then
  BASE_URL="http://localhost:4566/restapis/$API_ID/$STAGE/_user_request_"
else
  BASE_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE"
fi

FULL_URL="$BASE_URL$API_PATH"

# Print all available routes
log "Available routes on this API:"
$AWS_CMD apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query "items[?resourceMethods!=null].[keys(resourceMethods)[0], path]" \
  --output text | while IFS=$'\t' read -r m p; do
    if [ "$p" = "$API_PATH" ] && [ "$m" = "$METHOD" ]; then
      echo -e "  ${GREEN}➤ $m  $BASE_URL$p  ← testing this${RESET}"
    else
      echo -e "    $m  $BASE_URL$p"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — Build and run curl
# ─────────────────────────────────────────────────────────────────────────────
divider
echo -e "${BOLD}  SECTION 3 — Running Test${RESET}"
divider

log "Target: $METHOD $FULL_URL"

# Build curl args array
CURL_ARGS=(-X "$METHOD" "$FULL_URL" --max-time "$TIMEOUT" -s -w "\n__STATUS_CODE__:%{http_code}")

# Verbose flag
[ "$VERBOSE" = true ] && CURL_ARGS+=(-v)

# Extra headers
for header in "${EXTRA_HEADERS[@]}"; do
  CURL_ARGS+=(-H "$header")
done

# Body type: JSON or multipart
if [ -n "$JSON_BODY" ]; then
  # ── JSON mode ──────────────────────────────────────────────
  CURL_ARGS+=(-H "Content-Type: application/json")
  CURL_ARGS+=(-d "$JSON_BODY")
  info "Mode      : JSON body"
  info "Payload   : $JSON_BODY"

elif [ -n "$FILE_PATH" ] || [ ${#EXTRA_FIELDS[@]} -gt 0 ]; then
  # ── Multipart mode ─────────────────────────────────────────
  if [ -n "$FILE_PATH" ]; then
    [ ! -f "$FILE_PATH" ] && err "File not found: $FILE_PATH"
    CURL_ARGS+=(-F "file=@$FILE_PATH")
    info "Mode      : multipart/form-data"
    info "File      : $FILE_PATH ($(du -sh "$FILE_PATH" | cut -f1))"
  fi

  for field in "${EXTRA_FIELDS[@]}"; do
    CURL_ARGS+=(-F "$field")
    info "Field     : $field"
  done

else
  # ── No body (GET / HEAD etc.) ──────────────────────────────
  info "Mode      : no body ($METHOD)"
fi

echo ""
log "Executing..."
echo ""

# ── Run curl and capture response ─────────────────────────────────────────────
RESPONSE=$("${CURL_ARGS[@]}" 2>&1) || true
RAW_BODY=$(echo "$RESPONSE" | sed '/^__STATUS_CODE__/d')
STATUS_CODE=$(echo "$RESPONSE" | grep "__STATUS_CODE__" | cut -d: -f2)

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — Response analysis
# ─────────────────────────────────────────────────────────────────────────────
divider
echo -e "${BOLD}  SECTION 4 — Response${RESET}"
divider

# Colour the status code
if [[ "$STATUS_CODE" =~ ^2 ]]; then
  STATUS_DISPLAY="${GREEN}$STATUS_CODE OK${RESET}"
elif [[ "$STATUS_CODE" =~ ^4 ]]; then
  STATUS_DISPLAY="${YELLOW}$STATUS_CODE Client Error${RESET}"
elif [[ "$STATUS_CODE" =~ ^5 ]]; then
  STATUS_DISPLAY="${RED}$STATUS_CODE Server Error${RESET}"
else
  STATUS_DISPLAY="${CYAN}$STATUS_CODE${RESET}"
fi

echo -e "  HTTP Status : $STATUS_DISPLAY"
echo ""

# Pretty print if JSON, raw otherwise
echo -e "${BOLD}  Body:${RESET}"
echo "$RAW_BODY" | python3 -c "
import sys, json
raw = sys.stdin.read().strip()
try:
    parsed = json.loads(raw)
    # If body field itself is a JSON string, parse that too
    if 'body' in parsed and isinstance(parsed['body'], str):
        try:
            parsed['body'] = json.loads(parsed['body'])
        except:
            pass
    print(json.dumps(parsed, indent=2))
except:
    print(raw)
" 2>/dev/null || echo "$RAW_BODY"

# ── Diagnosis hints ───────────────────────────────────────────────────────────
echo ""
if [ "$STATUS_CODE" = "403" ]; then
  warn "403 — API Gateway is up but blocking the request."
  info "Check: resource policy, method auth, API key requirement"
elif [ "$STATUS_CODE" = "502" ]; then
  warn "502 — API Gateway reached Lambda but Lambda threw an error."
  info "Check: Lambda logs below for the stack trace"
elif [ "$STATUS_CODE" = "504" ]; then
  warn "504 — Lambda timed out. Current timeout: check Section 1 above."
elif [ "$STATUS_CODE" = "000" ]; then
  warn "000 — No response. Is LocalStack running? Is the URL reachable?"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — Lambda logs (optional, always shown on error)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$TAIL_LOGS" = true ] || [[ "$STATUS_CODE" =~ ^5 ]] || [ "$STATUS_CODE" = "000" ]; then
  divider
  echo -e "${BOLD}  SECTION 5 — Lambda Logs${RESET}"
  divider

  log "Fetching latest log stream..."
  sleep 2   # give CloudWatch a moment to flush

  LOG_STREAM=$($AWS_CMD logs describe-log-streams \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --order-by LastEventTime \
    --descending \
    --query "logStreams[0].logStreamName" \
    --output text 2>/dev/null) || warn "Could not fetch log streams."

  if [ -n "$LOG_STREAM" ] && [ "$LOG_STREAM" != "None" ]; then
    ok "Log stream: $LOG_STREAM"
    echo ""
    $AWS_CMD logs get-log-events \
      --log-group-name "/aws/lambda/$FUNCTION_NAME" \
      --log-stream-name "$LOG_STREAM" \
      --limit 50 \
      --query "events[*].message" \
      --output text 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -qi "error\|exception\|failed"; then
          echo -e "${RED}  $line${RESET}"
        elif echo "$line" | grep -qi "warn"; then
          echo -e "${YELLOW}  $line${RESET}"
        else
          echo -e "  $line"
        fi
    done
  else
    warn "No log streams found yet. Try running with -l again in a few seconds."
  fi
fi

divider
echo ""
