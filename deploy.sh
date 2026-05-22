#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "用法: $0 <product>"
  if [[ -d config ]]; then
    echo "可用產品: $(ls config 2>/dev/null | tr '\n' ' ')"
  fi
  exit 1
}

PRODUCT="${1:-}"
if [[ -z "${PRODUCT}" ]]; then
  usage
fi

CONFIG_FILE="config/${PRODUCT}/config.yaml"
QUERIES_DIR="queries/${PRODUCT}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[deploy] 找不到 ${CONFIG_FILE}"
  usage
fi
if [[ ! -d "${QUERIES_DIR}" ]]; then
  echo "[deploy] 找不到 ${QUERIES_DIR}"
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "[deploy] 需要 yq 來解析 YAML，請先安裝 (brew install yq)"
  exit 1
fi

read_yaml() {
  local val
  val=$(yq -r "$1" "${CONFIG_FILE}")
  [[ "${val}" == "null" ]] && val=""
  echo "${val}"
}

FUNCTION_NAME=$(read_yaml '.deploy.function_name')
LAMBDA_ROLE=$(read_yaml '.deploy.lambda_role')
ARCHITECTURE=$(read_yaml '.deploy.architecture')
TIMEOUT=$(read_yaml '.deploy.timeout')
MEMORY_SIZE=$(read_yaml '.deploy.memory_size')
REGION=$(read_yaml '.deploy.region')
AWS_PROFILE=$(read_yaml '.deploy.aws_profile')

[[ -z "${FUNCTION_NAME}" ]] && { echo "[deploy] deploy.function_name 為空"; exit 1; }
[[ -z "${LAMBDA_ROLE}"   ]] && { echo "[deploy] deploy.lambda_role 為空"; exit 1; }
[[ -z "${ARCHITECTURE}"  ]] && ARCHITECTURE="arm64"
[[ -z "${TIMEOUT}"       ]] && TIMEOUT=900
[[ -z "${MEMORY_SIZE}"   ]] && MEMORY_SIZE=1024

ZIP_PACKAGE="deployed_package_${PRODUCT}.zip"

log() { echo "[deploy:${PRODUCT}] $1"; }

aws_cmd() {
  local args=()
  [[ -n "${AWS_PROFILE}" ]] && args+=(--profile "${AWS_PROFILE}")
  [[ -n "${REGION}"      ]] && args+=(--region  "${REGION}")
  aws "${args[@]}" "$@"
}

build_package() {
  log "編譯 Go 執行檔 (GOOS=linux GOARCH=${ARCHITECTURE})..."
  GOOS=linux GOARCH="${ARCHITECTURE}" go build -tags lambda.norpc -o bootstrap ./cmd/main.go

  log "建立部署壓縮檔 ${ZIP_PACKAGE}..."
  rm -f "${ZIP_PACKAGE}"
  zip -r "${ZIP_PACKAGE}" bootstrap "config/${PRODUCT}" "queries/${PRODUCT}" >/dev/null
  ls -lh "${ZIP_PACKAGE}"
}

deploy_lambda() {
  if ! aws_cmd lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1; then
    log "函數不存在，建立 ${FUNCTION_NAME}"
    aws_cmd lambda create-function \
      --function-name "${FUNCTION_NAME}" \
      --runtime provided.al2023 \
      --handler bootstrap \
      --architectures "${ARCHITECTURE}" \
      --role "${LAMBDA_ROLE}" \
      --zip-file "fileb://${ZIP_PACKAGE}" \
      --timeout "${TIMEOUT}" \
      --memory-size "${MEMORY_SIZE}" \
      --environment "Variables={DEPLOY_TIME=$(date +%s),PRODUCT=${PRODUCT}}"
  else
    log "函數已存在，update-function-code"
    aws_cmd lambda update-function-code \
      --function-name "${FUNCTION_NAME}" \
      --zip-file "fileb://${ZIP_PACKAGE}"
  fi
}

cleanup() {
  log "清理暫存檔..."
  rm -f bootstrap "${ZIP_PACKAGE}"
}

main() {
  cleanup
  build_package
  deploy_lambda
  cleanup
  log "部署完成"
}

main "$@"
