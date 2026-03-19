#!/usr/bin/env bash
# =============================================================================
# Azure Blob Storage rclone 연결 및 mount 환경 검증 스크립트
#
# 사용법:
#   bash verify-azureblob.sh                         # 기본 점검
#   bash verify-azureblob.sh --remote azblob         # 특정 remote 연결 테스트
#   bash verify-azureblob.sh --remote azblob --container mycontainer --mount
#
# 옵션:
#   --remote NAME       rclone remote 이름 (연결 테스트)
#   --container NAME    컨테이너 이름 (ls 테스트)
#   --mount             실제 FUSE 마운트 동작 테스트
#   --conf FILE         rclone.conf 경로 (기본: /etc/rclone/rclone.conf)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
	echo -e "  ${GREEN}[PASS]${NC} $*"
	((PASS++))
}
check_fail() {
	echo -e "  ${RED}[FAIL]${NC} $*"
	((FAIL++))
}
check_warn() {
	echo -e "  ${YELLOW}[WARN]${NC} $*"
	((WARN++))
}
section() { echo -e "\n${BLUE}── $* ──${NC}"; }

# ── 인수 파싱 ─────────────────────────────────────────────────────────────────
RCLONE_CONF="/etc/rclone/rclone.conf"
REMOTE_NAME=""
CONTAINER_NAME=""
DO_MOUNT=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--remote)
		REMOTE_NAME="$2"
		shift 2
		;;
	--container)
		CONTAINER_NAME="$2"
		shift 2
		;;
	--mount)
		DO_MOUNT=true
		shift
		;;
	--conf)
		RCLONE_CONF="$2"
		shift 2
		;;
	-h | --help)
		sed -n '2,18p' "$0" | sed 's/^# \?//'
		exit 0
		;;
	*) shift ;;
	esac
done

# root 가 아니면 사용자 conf 폴백
if [[ ! -f "$RCLONE_CONF" ]] && [[ -f "${HOME}/.config/rclone/rclone.conf" ]]; then
	RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"
fi

echo ""
echo "=================================================="
echo "  rclone Azure Blob Storage 환경 검증"
echo "  conf: $RCLONE_CONF"
echo "=================================================="

# ═══════════════════════════════════════════════════════════════════════════════
section "1. rclone 바이너리"

if rclone_path=$(command -v rclone 2>/dev/null); then
	check_pass "rclone 발견: $rclone_path"
	ver=$(rclone version 2>/dev/null | head -1)
	check_pass "버전: $ver"
else
	check_fail "rclone 이 PATH에 없음. sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh 를 먼저 실행하세요."
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "2. rclone.conf 파일"

if [[ -f "$RCLONE_CONF" ]]; then
	check_pass "conf 파일 존재: $RCLONE_CONF"

	perms=$(stat -c "%a" "$RCLONE_CONF" 2>/dev/null || stat -f "%Lp" "$RCLONE_CONF" 2>/dev/null || echo "?")
	if [[ "$perms" == "600" ]] || [[ "$perms" == "640" ]]; then
		check_pass "파일 권한 안전: $perms"
	else
		check_warn "파일 권한: $perms (600 권장 → chmod 600 $RCLONE_CONF)"
	fi

	# azureblob remote 목록 추출
	AZURE_REMOTES=$(grep -E '^\[.+\]' "$RCLONE_CONF" | tr -d '[]' | while read -r name; do
		if grep -A 5 "^\[${name}\]" "$RCLONE_CONF" 2>/dev/null | grep -q "type.*=.*azureblob"; then
			echo "$name"
		fi
	done)

	if [[ -n "$AZURE_REMOTES" ]]; then
		check_pass "azureblob remote 발견:"
		while IFS= read -r r; do
			echo "        → [$r]"
			# 인증 방식 감지
			if grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^key\s*="; then
				echo "          인증: Account Key"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^sas_url\s*="; then
				echo "          인증: SAS URL"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^connection_string\s*="; then
				echo "          인증: Connection String"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^use_msi\s*=\s*true"; then
				echo "          인증: Managed Identity (MSI)"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^client_secret\s*="; then
				echo "          인증: Service Principal (Secret)"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^client_certificate_path\s*="; then
				echo "          인증: Service Principal (인증서)"
			elif grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "^env_auth\s*=\s*true"; then
				echo "          인증: env_auth"
			else
				echo "          인증: 알 수 없음"
			fi

			# disable_instance_discovery 확인
			if grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep -q "disable_instance_discovery\s*=\s*true"; then
				echo "          disable_instance_discovery: true (폐쇄망 모드)"
			else
				check_warn "  [$r] disable_instance_discovery 미설정 → 폐쇄망에서 login.microsoft.com 접근 시도 가능"
			fi

			# Private Endpoint 확인
			ep=$(grep -A 20 "^\[${r}\]" "$RCLONE_CONF" | grep "^endpoint\s*=" | awk -F= '{print $2}' | xargs || true)
			if [[ -n "$ep" ]]; then
				echo "          Private Endpoint: $ep"
			fi
		done <<<"$AZURE_REMOTES"
	else
		check_warn "azureblob type remote 가 conf 에 없습니다."
		echo "    → bash scripts/configure-azureblob.sh 로 설정하거나"
		echo "      azure/rclone-azureblob.conf 에서 원하는 섹션을 복사하세요."
	fi
else
	check_warn "conf 파일 없음: $RCLONE_CONF"
	echo "    → sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh 를 먼저 실행하거나"
	echo "      mkdir -p /etc/rclone && cp azure/rclone-azureblob.conf /etc/rclone/rclone.conf"
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "3. FUSE 환경 (mount용)"

if [[ -c /dev/fuse ]]; then
	check_pass "/dev/fuse 장치 존재"
else
	check_fail "/dev/fuse 없음 → sudo modprobe fuse"
fi

if command -v fusermount3 &>/dev/null; then
	check_pass "fusermount3: $(command -v fusermount3)"
elif command -v fusermount &>/dev/null; then
	check_warn "fusermount (v2) 만 발견. fuse3 패키지 설치 권장."
else
	check_fail "fusermount3 없음 → sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh"
fi

if [[ -f /etc/fuse.conf ]] && grep -q "^user_allow_other" /etc/fuse.conf; then
	check_pass "/etc/fuse.conf: user_allow_other 설정됨"
else
	check_warn "user_allow_other 미설정 (--allow-other 마운트 옵션 사용 시 필요)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "4. 네트워크 접근성"

ACCOUNT_FOR_NET=""
if [[ -f "$RCLONE_CONF" ]]; then
	ACCOUNT_FOR_NET=$(grep -A 20 "type.*=.*azureblob" "$RCLONE_CONF" | grep "^account\s*=" | head -1 | awk -F= '{print $2}' | xargs || true)
fi

if [[ -n "$ACCOUNT_FOR_NET" ]]; then
	TARGET="${ACCOUNT_FOR_NET}.blob.core.windows.net"
	info "Storage Account Blob endpoint 도달성 테스트: $TARGET"
	if curl -fsSL --max-time 10 --head "https://${TARGET}" &>/dev/null; then
		check_pass "HTTPS 접근 가능: https://${TARGET}"
	elif curl -fsSL --max-time 10 --head "https://${TARGET}" 2>&1 | grep -qE "SSL|certificate|tls"; then
		check_warn "TLS 연결은 됐으나 인증서 오류 (Private CA 환경 확인)"
	else
		check_warn "https://${TARGET} 접근 불가 (폐쇄망 정상 / Private Endpoint 확인)"
		echo "    → Private Endpoint 사용 시: DNS 오버라이드 및 endpoint 설정 확인"
		echo "    → curl -v https://${TARGET} 로 상세 확인"
	fi
else
	check_warn "Storage Account 이름을 conf 에서 찾지 못해 네트워크 테스트 건너뜀"
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "5. rclone 연결 테스트 (--remote 지정 시)"

if [[ -n "$REMOTE_NAME" ]]; then
	info "remote [$REMOTE_NAME] 연결 테스트 중..."

	if rclone lsd --config "$RCLONE_CONF" "${REMOTE_NAME}:" --contimeout 15s --timeout 30s 2>&1; then
		check_pass "[$REMOTE_NAME] 연결 성공 (컨테이너 목록 조회됨)"
	else
		EXIT_CODE=$?
		check_fail "[$REMOTE_NAME] 연결 실패 (exit=$EXIT_CODE)"
		echo ""
		echo "  일반적인 원인 및 해결책:"
		echo "  ┌─ Account Key 오류     → Azure Portal에서 Key 재확인"
		echo "  ├─ 네트워크 차단        → curl -v https://<account>.blob.core.windows.net"
		echo "  ├─ 방화벽/NSG          → Storage Account > Networking > Firewall 확인"
		echo "  ├─ Private Endpoint     → endpoint = 설정 및 DNS 오버라이드 확인"
		echo "  └─ AAD 토큰 실패        → disable_instance_discovery = true 추가"
	fi

	# 컨테이너 ls 테스트
	if [[ -n "$CONTAINER_NAME" ]]; then
		info "컨테이너 [$CONTAINER_NAME] 내용 조회 중..."
		if rclone ls --config "$RCLONE_CONF" "${REMOTE_NAME}:${CONTAINER_NAME}" \
			--contimeout 15s --timeout 30s 2>&1 | head -20; then
			check_pass "컨테이너 ls 성공"
		else
			check_fail "컨테이너 ls 실패"
		fi
	fi
else
	echo "  (--remote <이름> 옵션으로 연결 테스트 가능)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "6. FUSE 마운트 동작 테스트 (--mount 지정 시)"

if [[ "$DO_MOUNT" == true ]] && [[ -n "$REMOTE_NAME" ]] && [[ -n "$CONTAINER_NAME" ]]; then
	TMPDIR_MNT=$(mktemp -d /tmp/rclone-azure-mnt-XXXXXX)
	MOUNT_PID=""

	cleanup_mount() {
		if [[ -n "$MOUNT_PID" ]]; then
			kill "$MOUNT_PID" 2>/dev/null || true
			sleep 1
			fusermount3 -u "$TMPDIR_MNT" 2>/dev/null || fusermount -u "$TMPDIR_MNT" 2>/dev/null || true
		fi
		rmdir "$TMPDIR_MNT" 2>/dev/null || true
	}
	trap cleanup_mount EXIT

	info "마운트 테스트: ${REMOTE_NAME}:${CONTAINER_NAME} → $TMPDIR_MNT"

	rclone mount \
		--config "$RCLONE_CONF" \
		--vfs-cache-mode writes \
		--log-level ERROR \
		--contimeout 15s --timeout 30s \
		"${REMOTE_NAME}:${CONTAINER_NAME}" "$TMPDIR_MNT" &
	MOUNT_PID=$!
	sleep 3

	if mountpoint -q "$TMPDIR_MNT" 2>/dev/null || ls "$TMPDIR_MNT" &>/dev/null; then
		check_pass "Azure Blob 마운트 성공!"
		item_count=$(ls "$TMPDIR_MNT" 2>/dev/null | wc -l)
		echo "    → 마운트된 항목 수: $item_count"
	else
		check_fail "마운트 후 디렉토리 접근 실패"
	fi

	kill "$MOUNT_PID" 2>/dev/null || true
	MOUNT_PID=""
	sleep 1
	fusermount3 -u "$TMPDIR_MNT" 2>/dev/null || fusermount -u "$TMPDIR_MNT" 2>/dev/null || true
	trap - EXIT
	rmdir "$TMPDIR_MNT" 2>/dev/null || true
elif [[ "$DO_MOUNT" == true ]]; then
	check_warn "마운트 테스트 건너뜀 (--remote 와 --container 를 함께 지정해야 합니다)"
else
	echo "  (--mount --remote <이름> --container <컨테이너> 로 실제 마운트 테스트 가능)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "7. systemd 서비스 상태"

if command -v systemctl &>/dev/null; then
	running=$(systemctl list-units --type=service --state=running 2>/dev/null |
		grep "rclone" | awk '{print $1}' || true)
	if [[ -n "$running" ]]; then
		check_pass "실행 중인 rclone 서비스:"
		echo "$running" | sed 's/^/    → /'
	else
		echo "  (실행 중인 rclone 서비스 없음)"
	fi

	if [[ -f /etc/systemd/system/rclone-azureblob@.service ]]; then
		check_pass "rclone-azureblob@.service 템플릿 설치됨"
	else
		check_warn "rclone-azureblob@.service 미설치"
		echo "    → sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh 로 설치하거나"
		echo "      sudo cp systemd/rclone-azureblob@.service /etc/systemd/system/"
	fi
else
	check_warn "systemctl 없음 (systemd 환경 아님)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "=================================================="
echo "  검증 결과: PASS=$PASS  WARN=$WARN  FAIL=$FAIL"
if [[ $FAIL -eq 0 ]] && [[ $WARN -eq 0 ]]; then
	echo -e "  ${GREEN}✓ 모든 항목 정상. Azure Blob mount 사용 가능.${NC}"
elif [[ $FAIL -eq 0 ]]; then
	echo -e "  ${YELLOW}△ WARN 항목 확인 권장. 기본 동작은 가능.${NC}"
else
	echo -e "  ${RED}✗ FAIL 항목을 해결해야 합니다.${NC}"
fi
echo ""
echo "  빠른 사용 예시:"
echo "  bash scripts/configure-azureblob.sh          # 설정 추가"
echo "  bash scripts/verify-azureblob.sh --remote <NAME> --container <CONT> --mount"
echo "=================================================="

exit $FAIL
