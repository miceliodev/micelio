if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_PATH="${(%):-%x}"
else
  SCRIPT_PATH="${0}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTANCE_FILE="${PROJECT_ROOT}/.micelio-dev-instance"

validate_suffix() {
  local suffix="$1"

  [[ "$suffix" =~ ^[0-9]+$ ]] || return 1
  (( suffix >= 1 && suffix <= 999 ))
}

ensure_suffix() {
  local suffix=""

  if [[ -n "${MICELIO_DEV_INSTANCE:-}" ]]; then
    suffix="${MICELIO_DEV_INSTANCE}"
  elif [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  else
    suffix="$(awk 'BEGIN { srand(); print int(100 + rand() * 900) }')"
  fi

  validate_suffix "${suffix}" || {
    echo "Invalid dev instance suffix '${suffix}'. Expected an integer between 1 and 999." >&2
    return 1
  }

  printf '%s' "${suffix}" > "${INSTANCE_FILE}"
  printf '%s' "${suffix}"
}

suffix="$(ensure_suffix)"
test_partition="${MIX_TEST_PARTITION:-}"

export MICELIO_DEV_INSTANCE="${suffix}"
export MICELIO_DEV_PORT="$((4000 + suffix))"
export MICELIO_DEV_GRPC_PORT="$((50051 + suffix))"
export MICELIO_DEV_POSTGRES_DB="micelio_dev_${suffix}"
export MICELIO_TEST_PORT="$((4002 + suffix))"
export MICELIO_TEST_POSTGRES_DB="micelio_test${test_partition}_${suffix}"
