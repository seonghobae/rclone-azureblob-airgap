#!/usr/bin/env bash
# =============================================================================
# Azure Blob Storage rclone 설정 도우미
# 인터랙티브하게 rclone.conf 에 Azure Blob remote 를 추가합니다.
# 폐쇄망에서 rclone config 인터랙티브 모드 대신 이 스크립트를 사용하세요.
#
# 사용법:
#   bash configure-azureblob.sh
#   bash configure-azureblob.sh --conf /path/to/rclone.conf
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() {
	echo -e "${RED}[FAIL]${NC}  $*" >&2
	exit 1
}
ask() { echo -e "${CYAN}[INPUT]${NC} $*"; }

# ── 설정 파일 경로 ────────────────────────────────────────────────────────────
RCLONE_CONF="/etc/rclone/rclone.conf"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--conf)
		RCLONE_CONF="$2"
		shift 2
		;;
	-h | --help)
		echo "사용법: bash configure-azureblob.sh [--conf /path/to/rclone.conf]"
		exit 0
		;;
	*) shift ;;
	esac
done

# root 가 아니면 홈 디렉토리 conf 사용
if [[ $EUID -ne 0 ]] && [[ "$RCLONE_CONF" == "/etc/rclone/rclone.conf" ]]; then
	RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"
	warn "root 가 아니므로 사용자 설정 경로를 사용합니다: $RCLONE_CONF"
fi

mkdir -p "$(dirname "$RCLONE_CONF")"
touch "$RCLONE_CONF"
chmod 600 "$RCLONE_CONF"

echo ""
echo -e "${BOLD}=================================================="
echo "  rclone Azure Blob Storage 설정 도우미"
echo -e "==================================================${NC}"
echo ""

# ── remote 이름 ───────────────────────────────────────────────────────────────
ask "remote 이름을 입력하세요 (예: azblob, myblob, prodblob) [기본값: azblob]:"
read -r REMOTE_NAME
REMOTE_NAME="${REMOTE_NAME:-azblob}"

# 이미 존재하는지 확인
if grep -q "^\[${REMOTE_NAME}\]" "$RCLONE_CONF" 2>/dev/null; then
	warn "[$REMOTE_NAME] 이 이미 $RCLONE_CONF 에 존재합니다."
	ask "덮어쓰겠습니까? (y/N):"
	read -r OVERWRITE
	if [[ "${OVERWRITE,,}" != "y" ]]; then
		info "취소되었습니다. 다른 이름을 사용하거나 파일을 직접 편집하세요."
		exit 0
	fi
	# 기존 섹션 제거 (BEGIN ~ 다음 [ 이전까지)
	python3 - "$RCLONE_CONF" "$REMOTE_NAME" <<'PYEOF'
import sys, re
conf_path, section = sys.argv[1], sys.argv[2]
with open(conf_path) as f:
    content = f.read()
# 섹션 제거: [name] 부터 다음 [섹션] 전까지
pattern = r'\[' + re.escape(section) + r'\][^\[]*'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open(conf_path, 'w') as f:
    f.write(content.strip() + '\n')
PYEOF
fi

# ── Storage Account 이름 ──────────────────────────────────────────────────────
echo ""
ask "Azure Storage Account 이름 (예: mystorageaccount):"
read -r ACCOUNT_NAME
[[ -z "$ACCOUNT_NAME" ]] && fail "Storage Account 이름은 필수입니다."

# ── Private Endpoint ──────────────────────────────────────────────────────────
echo ""
info "Private Endpoint 설정 (폐쇄망에서 Azure Storage Private Link 사용 시)"
ask "Private Endpoint URL을 사용합니까? (y/N):"
read -r USE_PRIVATE
ENDPOINT_LINE=""
if [[ "${USE_PRIVATE,,}" == "y" ]]; then
	ask "Blob Endpoint FQDN (예: https://mystorageaccount.blob.core.windows.net):"
	read -r ENDPOINT_URL
	ENDPOINT_URL="${ENDPOINT_URL:-https://${ACCOUNT_NAME}.blob.core.windows.net}"
	ENDPOINT_LINE="endpoint             = ${ENDPOINT_URL}"
fi

# ── 인증 방식 선택 ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}인증 방식을 선택하세요:${NC}"
echo "  1) Account Key (Shared Key)     — 가장 간단, 폐쇄망 권장"
echo "  2) SAS URL                      — 임시/제한 접근 URL"
echo "  3) Connection String            — Azure Portal 연결 문자열"
echo "  4) Service Principal (Secret)   — 앱 등록 + Client Secret"
echo "  5) Service Principal (인증서)   — 앱 등록 + PEM/PKCS12"
echo "  6) Managed Identity (MSI)       — Azure VM 전용"
echo "  7) env_auth                     — 환경 변수 / CLI 자동 탐색"
echo ""
ask "번호 입력 [1-7]:"
read -r AUTH_CHOICE

AUTH_BLOCK=""
DISABLE_DISCOVERY="disable_instance_discovery = true"

case "$AUTH_CHOICE" in
1)
	ask "Storage Account Key (Base64 인코딩된 키):"
	read -rs ACCOUNT_KEY
	echo
	[[ -z "$ACCOUNT_KEY" ]] && fail "Account Key는 필수입니다."
	AUTH_BLOCK="key                  = ${ACCOUNT_KEY}"
	;;
2)
	ask "SAS URL (https://...?sv=...&sig=... 전체):"
	read -r SAS_URL
	[[ -z "$SAS_URL" ]] && fail "SAS URL은 필수입니다."
	# SAS URL 사용 시 account 필드는 비워둠
	ACCOUNT_NAME=""
	AUTH_BLOCK="sas_url              = ${SAS_URL}"
	;;
3)
	ask "Connection String (DefaultEndpointsProtocol=https;... 전체):"
	read -r CONN_STR
	[[ -z "$CONN_STR" ]] && fail "Connection String은 필수입니다."
	ACCOUNT_NAME=""
	AUTH_BLOCK="connection_string    = ${CONN_STR}"
	;;
4)
	ask "Tenant ID (디렉터리 ID, GUID):"
	read -r TENANT_ID
	ask "Client ID (앱 등록 클라이언트 ID, GUID):"
	read -r CLIENT_ID
	ask "Client Secret:"
	read -rs CLIENT_SECRET
	echo
	[[ -z "$TENANT_ID" || -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]] && fail "Tenant ID, Client ID, Client Secret 모두 필수입니다."
	AUTH_BLOCK="tenant               = ${TENANT_ID}
client_id            = ${CLIENT_ID}
client_secret        = ${CLIENT_SECRET}"
	;;
5)
	ask "Tenant ID (GUID):"
	read -r TENANT_ID
	ask "Client ID (GUID):"
	read -r CLIENT_ID
	ask "인증서 파일 경로 (PEM 또는 PKCS12, 예: /etc/rclone/certs/sp-cert.pem):"
	read -r CERT_PATH
	ask "인증서 암호 (없으면 Enter):"
	read -rs CERT_PASS
	echo

	if [[ -z "$CERT_PASS" ]]; then
		CERT_PASS_LINE=""
	else
		# rclone obscure 로 암호화
		if command -v rclone &>/dev/null; then
			OBS_PASS=$(rclone obscure "$CERT_PASS")
			CERT_PASS_LINE="client_certificate_password = ${OBS_PASS}"
		else
			warn "rclone 이 PATH에 없어 암호를 obscure 처리할 수 없습니다."
			warn "나중에 수동으로: rclone obscure '<암호>' 실행 후 conf에 추가"
			CERT_PASS_LINE="# client_certificate_password = <rclone obscure 실행 결과>"
		fi
	fi
	AUTH_BLOCK="tenant               = ${TENANT_ID}
client_id            = ${CLIENT_ID}
client_certificate_path = ${CERT_PATH}
${CERT_PASS_LINE}
client_send_certificate_chain = false"
	;;
6)
	echo ""
	info "Managed Identity 설정"
	echo "  a) 시스템 할당 관리 ID   (VM에 하나만 있는 경우)"
	echo "  b) 사용자 할당 관리 ID  (Client ID 지정)"
	ask "선택 (a/b) [기본: a]:"
	read -r MSI_TYPE
	case "${MSI_TYPE:-a}" in
	b)
		ask "사용자 할당 MSI Client ID (GUID):"
		read -r MSI_CLIENT
		AUTH_BLOCK="use_msi              = true
msi_client_id        = ${MSI_CLIENT}"
		;;
	*)
		AUTH_BLOCK="use_msi              = true"
		;;
	esac
	;;
7)
	AUTH_BLOCK="env_auth             = true"
	warn "env_auth 모드: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET 환경 변수 또는 'az login' 필요"
	;;
*)
	fail "잘못된 선택: $AUTH_CHOICE"
	;;
esac

# ── 성능 튜닝 ─────────────────────────────────────────────────────────────────
echo ""
ask "업로드 병렬도 (기본 16, 1Gbps 링크면 32~64 권장):"
read -r UPLOAD_CONCURRENCY
UPLOAD_CONCURRENCY="${UPLOAD_CONCURRENCY:-16}"

ask "청크 크기 (기본 4M, 대용량 파일이면 16M 권장):"
read -r CHUNK_SIZE
CHUNK_SIZE="${CHUNK_SIZE:-4M}"

ask "Access Tier (hot/cool/cold/archive, 기본 hot, 비워두면 계정 기본값):"
read -r ACCESS_TIER

ACCESS_TIER_LINE=""
if [[ -n "$ACCESS_TIER" ]]; then
	ACCESS_TIER_LINE="access_tier          = ${ACCESS_TIER}"
fi

# ── conf 생성 ─────────────────────────────────────────────────────────────────
echo ""
info "rclone.conf 에 [$REMOTE_NAME] 섹션 추가 중..."

{
	echo ""
	echo "[${REMOTE_NAME}]"
	echo "type                 = azureblob"
	[[ -n "$ACCOUNT_NAME" ]] && echo "account              = ${ACCOUNT_NAME}"
	[[ -n "$AUTH_BLOCK" ]] && echo "${AUTH_BLOCK}"
	[[ -n "$ENDPOINT_LINE" ]] && echo "${ENDPOINT_LINE}"
	echo "${DISABLE_DISCOVERY}"
	echo "upload_concurrency   = ${UPLOAD_CONCURRENCY}"
	echo "chunk_size           = ${CHUNK_SIZE}"
	[[ -n "$ACCESS_TIER_LINE" ]] && echo "${ACCESS_TIER_LINE}"
	echo "directory_markers    = false"
} >>"$RCLONE_CONF"

echo ""
ok "설정 추가 완료: $RCLONE_CONF"
echo ""
echo "추가된 섹션:"
echo "──────────────────────────────────────"
# 마지막 섹션 출력 (보안: key/secret 일부 마스킹)
grep -A 30 "^\[${REMOTE_NAME}\]" "$RCLONE_CONF" |
	sed '/^\[.*\]$/{ /^\['"${REMOTE_NAME}"'\]/!q }' |
	sed 's/\(key\s*=\s*\).\{8\}.*/\1***MASKED***/i' |
	sed 's/\(secret\s*=\s*\).\{8\}.*/\1***MASKED***/i' |
	sed 's/\(password\s*=\s*\).\{4\}.*/\1***MASKED***/i' |
	sed 's/\(sas_url\s*=\s*https:\/\/[^?]*\).*/\1?***MASKED***/'
echo "──────────────────────────────────────"
echo ""

# ── 연결 테스트 ───────────────────────────────────────────────────────────────
if command -v rclone &>/dev/null; then
	echo ""
	ask "지금 연결 테스트를 실행하겠습니까? (컨테이너 목록 조회) (Y/n):"
	read -r DO_TEST
	if [[ "${DO_TEST,,}" != "n" ]]; then
		info "rclone lsd ${REMOTE_NAME}: 실행 중..."
		if rclone lsd --config "$RCLONE_CONF" "${REMOTE_NAME}:" 2>&1; then
			ok "연결 성공! 컨테이너 목록 출력됨."
		else
			warn "연결 실패. 설정을 확인하거나 네트워크 접근성을 점검하세요."
			warn "파일 직접 편집: vi $RCLONE_CONF"
		fi
	fi
else
	warn "rclone 이 PATH에 없습니다. install.sh 를 먼저 실행하세요."
fi

echo ""
echo "── 다음 단계 ──────────────────────────────────────"
echo "  # 컨테이너 목록"
echo "  rclone lsd ${REMOTE_NAME}:"
echo ""
echo "  # 파일 목록"
echo "  rclone ls ${REMOTE_NAME}:<컨테이너이름>"
echo ""
echo "  # 마운트 (포어그라운드)"
echo "  mkdir -p /mnt/azureblob"
echo "  rclone mount ${REMOTE_NAME}:<컨테이너> /mnt/azureblob --vfs-cache-mode writes &"
echo ""
echo "  # systemd 서비스 마운트"
echo "  cp azure/conf-examples/azblob-key.conf /etc/rclone/mounts/${REMOTE_NAME}.conf"
echo "  vi /etc/rclone/mounts/${REMOTE_NAME}.conf"
echo "  systemctl start rclone-azureblob@${REMOTE_NAME}.service"
echo "────────────────────────────────────────────────────"
