#!/usr/bin/env bash
# verify-prod.sh — valida o estado dos serviços Agenteresolve em produção.
#
# Uso:
#   bash verify-prod.sh                      # roda todas as checagens
#   bash verify-prod.sh --only translate,ocr # filtra por nome/subdomínio
#   bash verify-prod.sh --json               # saída JSON (para CI)
#   bash verify-prod.sh --quiet              # só o resultado final
#   bash verify-prod.sh --timeout 30 --retries 3
#   bash verify-prod.sh --no-optional        # ignora checagens opcionais
#
# Sai com código 0 se tudo passar; 1 se houver falha em checagem obrigatória.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for candidate in "$PWD/.env.deploy" "$SCRIPT_DIR/.env.deploy" "$SCRIPT_DIR/../.env.deploy"; do
  if [[ -f "$candidate" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$candidate"
    set +a
    break
  fi
done

ZONE="${CF_ZONE:-agenteresolve.com.br}"
TIMEOUT="${VERIFY_TIMEOUT:-20}"
RETRIES="${VERIFY_RETRIES:-2}"
ONLY="${VERIFY_ONLY:-}"
JSON=0
QUIET=0
RUN_OPTIONAL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --retries) RETRIES="$2"; shift 2 ;;
    --no-optional) RUN_OPTIONAL=0; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
  esac
done

if [[ -t 1 && "$JSON" -eq 0 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_RESET=''
fi

PASSES=0
FAILURES=0
WARNINGS=0
declare -a JSON_ROWS=()

# check <name> <url> <expected_status> [marker] [method] [optional]
check() {
  local name="$1" url="$2" expected="$3" marker="${4:-}" method="${5:-GET}" optional="${6:-0}"

  if [[ -n "$ONLY" ]]; then
    local matched=0
    IFS=',' read -ra filters <<< "$ONLY"
    for filter in "${filters[@]}"; do
      [[ "$name" == *"$filter"* || "$url" == *"$filter"* ]] && matched=1
    done
    [[ "$matched" -eq 0 ]] && return
  fi

  if [[ "$optional" == "1" && "$RUN_OPTIONAL" -eq 0 ]]; then
    return
  fi

  local body_file status attempt=0
  body_file="$(mktemp)"

  while true; do
    attempt=$((attempt + 1))
    if [[ "$method" == "POST" ]]; then
      status="$(curl -sS -o "$body_file" -w '%{http_code}' -m "$TIMEOUT" -X POST "$url" 2>/dev/null)" || status=000
    else
      status="$(curl -sS -o "$body_file" -w '%{http_code}' -m "$TIMEOUT" "$url" 2>/dev/null)" || status=000
    fi
    [[ "$status" =~ ^[0-9]{3}$ ]] || status=000
    [[ "$status" != "000" ]] && break
    [[ "$attempt" -gt "$RETRIES" ]] && break
    sleep 1
  done

  local ok=1 reason=""
  if [[ "$status" != "$expected" ]]; then
    ok=0
    reason="status $status (esperado $expected)"
  elif [[ -n "$marker" ]] && ! grep -qi -- "$marker" "$body_file" 2>/dev/null; then
    ok=0
    reason="conteúdo esperado não encontrado: '$marker'"
  fi

  local snippet=""
  if [[ "$ok" -eq 0 && -z "$marker" ]]; then
    snippet="$(head -c 160 "$body_file" 2>/dev/null | tr '\n' ' ')"
  fi
  rm -f "$body_file"

  local json_status="$status"
  [[ "$json_status" == "000" ]] && json_status=0

  if [[ "$ok" -eq 1 ]]; then
    PASSES=$((PASSES + 1))
    [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]] && printf '  %s%-6s%s %s\n' "$C_GREEN" "OK" "$C_RESET" "$name"
    JSON_ROWS+=("{\"name\":\"$name\",\"url\":\"$url\",\"status\":$json_status,\"ok\":true,\"optional\":$([[ $optional == 1 ]] && echo true || echo false)}")
  elif [[ "$optional" == "1" ]]; then
    WARNINGS=$((WARNINGS + 1))
    [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]] && printf '  %s%-6s%s %s %s(%s)%s\n' "$C_YELLOW" "WARN" "$C_RESET" "$name" "$C_DIM" "$reason" "$C_RESET"
    JSON_ROWS+=("{\"name\":\"$name\",\"url\":\"$url\",\"status\":$json_status,\"ok\":false,\"optional\":true}")
  else
    FAILURES=$((FAILURES + 1))
    [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]] && printf '  %s%-6s%s %s %s(%s)%s %s\n' "$C_RED" "FAIL" "$C_RESET" "$name" "$C_DIM" "$reason" "$C_RESET" "$snippet"
    JSON_ROWS+=("{\"name\":\"$name\",\"url\":\"$url\",\"status\":$json_status,\"ok\":false,\"optional\":false,\"reason\":\"$reason\"}")
  fi
}

FRONTENDS=(tools louder translate docuextract askyourdocs datachat feedback seo contracts ocr anonymize alttext objectcount transcribe tts audio-enhance voicechat)

if [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]]; then
  echo "Verificando produção em $ZONE (timeout ${TIMEOUT}s, retries ${RETRIES})"
  echo
  echo "Frontends (Cloudflare Pages)"
fi
for slug in "${FRONTENDS[@]}"; do
  marker="agenteresolve"
  [[ "$slug" == "louder" ]] && marker=""
  check "frontend:$slug" "https://$slug.$ZONE" 200 "$marker" "GET" 0
done

if [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]]; then echo; echo "Site institucional"; fi
check "site:home" "https://$ZONE/pt" 200 "" "GET" 0
check "site:admin-login" "https://$ZONE/app/login" 200 "" "GET" 0
check "site:health" "https://$ZONE/health" 200 "\"status\":\"ok\"" "GET" 0

if [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]]; then echo; echo "Gateway e backends"; fi
check "gateway:health" "https://api.$ZONE/health" 200 "\"status\":\"ok\"" "GET" 0
# Clerk ainda não configurado em produção: AUTH_REQUIRED=false faz /api/auth/me
# responder 200 (local-dev) em vez de 401. Vira aviso até as chaves Clerk entrarem.
check "gateway:auth-required" "https://api.$ZONE/api/auth/me" 401 "" "GET" 1
check "backend:translate-api" "https://translate-api.$ZONE/health" 200 "" "GET" 0

if [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]]; then echo; echo "Privados"; fi
check "coder:private" "https://coder.$ZONE" 401 "" "GET" 0
check "coder:runner" "https://coder.$ZONE/runner/ping" 200 "agenteresolve-runner" "GET" 0
check "code-server:login" "https://code.$ZONE/login" 200 "" "GET" 0

if [[ "$QUIET" -eq 0 && "$JSON" -eq 0 ]]; then echo; echo "Opcionais"; fi
check "inference:health" "https://inference.$ZONE/health" 200 "" "GET" 1

TOTAL=$((PASSES + FAILURES + WARNINGS))

if [[ "$JSON" -eq 1 ]]; then
  printf '{"zone":"%s","total":%d,"passed":%d,"failed":%d,"warnings":%d,"checks":[%s]}\n' \
    "$ZONE" "$TOTAL" "$PASSES" "$FAILURES" "$WARNINGS" "$(IFS=,; echo "${JSON_ROWS[*]}")"
else
  echo
  if [[ "$FAILURES" -eq 0 ]]; then
    printf '%s%d/%d ok%s' "$C_GREEN" "$PASSES" "$TOTAL" "$C_RESET"
  else
    printf '%s%d/%d ok, %d falha(s)%s' "$C_RED" "$PASSES" "$TOTAL" "$FAILURES" "$C_RESET"
  fi
  [[ "$WARNINGS" -gt 0 ]] && printf ', %d aviso(s)' "$WARNINGS"
  echo
fi

[[ "$FAILURES" -eq 0 ]] && exit 0 || exit 1
