#!/usr/bin/env bash
# =============================================================================
# rclone mount 환경 검증 스크립트
# 설치 후 FUSE / mount 동작 가능 여부를 빠르게 점검합니다.
# 실제 remote 없이 로컬 경로만으로 동작 확인합니다.
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
ALLOW_MISSING_FUSE=false

check_pass() {
	echo -e "  ${GREEN}[PASS]${NC} $*"
	PASS=$((PASS + 1))
}
check_fail() {
	echo -e "  ${RED}[FAIL]${NC} $*"
	FAIL=$((FAIL + 1))
}
check_warn() {
	echo -e "  ${YELLOW}[WARN]${NC} $*"
	WARN=$((WARN + 1))
}
section() { echo -e "\n${BLUE}── $* ──${NC}"; }

while [[ $# -gt 0 ]]; do
	case "$1" in
	--allow-missing-fuse)
		ALLOW_MISSING_FUSE=true
		shift
		;;
	-h | --help)
		echo "사용법: bash verify-mount.sh [--allow-missing-fuse]"
		echo "  --allow-missing-fuse  CI/컨테이너 등 /dev/fuse 없는 환경에서 FUSE 커널 장치 부재를 WARN으로 처리"
		exit 0
		;;
	*) shift ;;
	esac
done

section "1. rclone 바이너리"
if rclone_path=$(command -v rclone 2>/dev/null); then
	check_pass "rclone 발견: $rclone_path"
	ver=$(rclone version 2>/dev/null | head -1)
	check_pass "버전: $ver"
else
	check_fail "rclone 이 PATH에 없음. sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh 를 먼저 실행하세요."
fi

section "2. FUSE 커널 모듈"
if [[ -c /dev/fuse ]]; then
	check_pass "/dev/fuse 장치 존재"
	perm=$(stat -c "%a" /dev/fuse 2>/dev/null || stat -f "%Lp" /dev/fuse 2>/dev/null || echo "unknown")
	if [[ "$perm" == "666" ]] || [[ "$perm" == "660" ]]; then
		check_pass "/dev/fuse 권한: $perm"
	else
		check_warn "/dev/fuse 권한: $perm (666 이 권장됨 → sudo chmod 666 /dev/fuse)"
	fi
else
	if [[ "$ALLOW_MISSING_FUSE" == true ]]; then
		check_warn "/dev/fuse 없음 (CI/비-privileged 환경 허용 모드)"
	else
		check_fail "/dev/fuse 없음"
	fi
	echo "    → 시도: sudo modprobe fuse"
	echo "    → VM 이면: VM 설정에서 /dev/fuse passthrough 또는 privileged 실행 필요"
fi

section "3. FUSE3 라이브러리"
if command -v dpkg &>/dev/null; then
	if dpkg -l libfuse3-3 2>/dev/null | grep -q "^ii"; then
		ver=$(dpkg -l libfuse3-3 2>/dev/null | awk '/^ii/{print $3}')
		check_pass "libfuse3-3 설치됨: $ver"
	elif
		path=$(find /lib /usr/lib -name libfuse3.so.3 -print -quit 2>/dev/null)
		[[ -n "$path" ]]
	then
		check_pass "libfuse3 runtime 사용 가능: $path"
	else
		check_fail "libfuse3 runtime 미확인 → sudo dpkg -i rclone-azureblob-airgap_*.deb  (또는) sudo bash /usr/share/rclone-azureblob-airgap/scripts/install.sh 실행"
	fi

	if dpkg -l fuse3 2>/dev/null | grep -q "^ii"; then
		ver=$(dpkg -l fuse3 2>/dev/null | awk '/^ii/{print $3}')
		check_pass "fuse3 설치됨: $ver"
	elif command -v fusermount3 &>/dev/null; then
		check_pass "fuse3 runtime 사용 가능: $(command -v fusermount3)"
	else
		check_warn "fuse3 패키지 미설치 (fusermount3 없을 수 있음)"
	fi
else
	check_warn "dpkg 없음 (Ubuntu가 아닐 수 있음)"
fi

section "4. fusermount3 명령어"
if command -v fusermount3 &>/dev/null; then
	check_pass "fusermount3 발견: $(command -v fusermount3)"
elif command -v fusermount &>/dev/null; then
	check_warn "fusermount (v2) 발견. fusermount3 가 권장됩니다."
else
	check_fail "fusermount3 없음 → fuse3 패키지 설치 필요"
fi

section "5. /etc/fuse.conf"
if [[ -f /etc/fuse.conf ]]; then
	if grep -q "^user_allow_other" /etc/fuse.conf; then
		check_pass "user_allow_other 설정됨"
	else
		check_warn "user_allow_other 미설정 (--allow-other 옵션 사용 시 필요)"
	fi
else
	check_warn "/etc/fuse.conf 없음"
fi

section "6. rclone 로컬 마운트 동작 테스트"
# 실제 remote 없이 local 백엔드로 마운트 테스트
TMPDIR_SRC=$(mktemp -d /tmp/rclone-src-XXXXXX)
TMPDIR_MNT=$(mktemp -d /tmp/rclone-mnt-XXXXXX)
echo "test-content-$(date +%s)" >"$TMPDIR_SRC/test.txt"

# rclone mount는 백그라운드로 실행
MOUNT_PID=""
cleanup() {
	if [[ -n "$MOUNT_PID" ]]; then
		kill "$MOUNT_PID" 2>/dev/null || true
		sleep 0.5
		fusermount3 -u "$TMPDIR_MNT" 2>/dev/null || fusermount -u "$TMPDIR_MNT" 2>/dev/null || true
	fi
	rm -rf "$TMPDIR_SRC" "$TMPDIR_MNT" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -c /dev/fuse ]]; then
	rclone mount ":local:$TMPDIR_SRC" "$TMPDIR_MNT" \
		--vfs-cache-mode off --daemon-timeout 5s \
		--log-level ERROR &
	MOUNT_PID=$!
	sleep 2

	if [[ -f "$TMPDIR_MNT/test.txt" ]]; then
		check_pass "로컬 마운트 테스트 성공! (파일 접근 확인)"
	else
		check_warn "마운트 파일 접근 불가 (마운트는 됐으나 파일 미노출)"
	fi
	kill "$MOUNT_PID" 2>/dev/null || true
	MOUNT_PID=""
	sleep 0.5
	fusermount3 -u "$TMPDIR_MNT" 2>/dev/null || fusermount -u "$TMPDIR_MNT" 2>/dev/null || true
else
	check_warn "마운트 테스트 건너뜀 (/dev/fuse 없음)"
fi

section "7. fuse 그룹"
if getent group fuse &>/dev/null; then
	check_pass "fuse 그룹 존재"
	CURRENT_USER="${SUDO_USER:-$USER}"
	if id -nG "$CURRENT_USER" 2>/dev/null | grep -qw fuse; then
		check_pass "$CURRENT_USER 가 fuse 그룹 구성원"
	else
		check_warn "$CURRENT_USER 가 fuse 그룹에 없음"
		echo "    → sudo usermod -aG fuse $CURRENT_USER"
		echo "    → 재로그인 후 적용됩니다."
	fi
else
	check_warn "fuse 그룹 없음 (sudo 없이 mount 하려면 필요)"
fi

# ── 최종 결과 ─────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "  검증 결과: PASS=$PASS  WARN=$WARN  FAIL=$FAIL"
if [[ $FAIL -eq 0 ]]; then
	echo -e "  ${GREEN}✓ 환경 준비 완료. rclone mount 사용 가능.${NC}"
else
	echo -e "  ${RED}✗ 위의 FAIL 항목을 해결하세요.${NC}"
fi
echo "=================================================="

exit $FAIL
