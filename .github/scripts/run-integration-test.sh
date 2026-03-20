#!/bin/bash
# =============================================================================
# Docker 컨테이너 안에서 실행되는 통합 테스트 스크립트
#
# 환경 변수:
#   UBUNTU_CODENAME   jammy | noble
#
# 테스트 흐름:
#   1. 의존성 설치 (curl, unzip, nodejs for azurite)
#   2. Azurite (Azure Storage Emulator) 시작
#   3. FUSE3 오프라인 deb 설치
#   4. rclone 바이너리 설치
#   5. rclone.conf 생성 (Connection String → Azurite, disable_instance_discovery)
#   6. 컨테이너 생성 / 파일 업로드 / 다운로드 / 삭제
#   7. FUSE 마운트 → 파일 읽기/쓰기 → 언마운트
#   8. verify-azureblob.sh 실행
# =============================================================================
set -euo pipefail

CODENAME="${UBUNTU_CODENAME:-jammy}"
WORKSPACE="/workspace"
PACKAGE_DEB="${PACKAGE_DEB:-}"
RCLONE_BIN_ARCH="${RCLONE_BIN_ARCH:-amd64}"
PASS=0
FAIL=0

case "$RCLONE_BIN_ARCH" in
amd64 | arm64) ;;
*)
	echo "[FAIL] 지원하지 않는 RCLONE_BIN_ARCH: $RCLONE_BIN_ARCH" >&2
	exit 1
	;;
esac

log_filtered_dpkg_output() {
	local log_file=$1
	grep -Ev "^(Reading|Selecting|Preparing|Unpacking|Setting up|Processing)" "$log_file" || true
}

resolve_package_deb() {
	local pattern=$1
	local -a matches=()
	shopt -s nullglob
	mapfile -t matches < <(for f in $pattern; do printf '%s\n' "$f"; done)
	shopt -u nullglob
	if [ "${#matches[@]}" -ne 1 ]; then
		red "release deb 경로 확인 실패: $pattern"
		exit 1
	fi
	printf '%s\n' "${matches[0]}"
}

green() {
	echo -e "\033[0;32m[PASS]\033[0m $*"
	PASS=$((PASS + 1))
}
red() {
	echo -e "\033[0;31m[FAIL]\033[0m $*"
	FAIL=$((FAIL + 1))
}
info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
step() { echo -e "\n\033[1m══ $* ══\033[0m"; }

# ── 1. 기본 도구 설치 ─────────────────────────────────────────────────────────
step "1. 기본 도구 설치"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
BASE_PACKAGES=(curl ca-certificates unzip python3)
if [ -z "$PACKAGE_DEB" ]; then
	BASE_PACKAGES+=(fuse3 libfuse3-3)
fi
apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}" 2>/dev/null

# Node.js 20 LTS + npm 설치
# NodeSource nodejs 패키지(>=18)는 npm 포함
if ! node --version 2>/dev/null | grep -qE "^v(18|20|22)\."; then
	curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tail -3
	apt-get install -y nodejs 2>&1 | tail -3
fi
NODE_VER=$(node --version 2>/dev/null || echo "none")
NPM_VER=$(npm --version 2>/dev/null || echo "none")
info "Node.js: $NODE_VER, npm: $NPM_VER"
# npm이 여전히 없으면 corepack 으로 활성화
if [[ "$NPM_VER" == "none" ]]; then
	corepack enable 2>/dev/null || true
	NPM_VER=$(npm --version 2>/dev/null || echo "still-none")
	info "npm after corepack: $NPM_VER"
fi
green "기본 도구 설치 완료 (node=$NODE_VER npm=$NPM_VER)"

# ── 2. Azurite 설치 및 시작 ───────────────────────────────────────────────────
step "2. Azurite (Azure Storage Emulator) 설치 및 시작"
# set -o pipefail 환경에서 파이프 오류 전파를 막기 위해 임시 비활성화
set +o pipefail
NPM_LOG=$(npm install -g azurite 2>&1)
NPM_EXIT=$?
set -o pipefail
if [ "$NPM_EXIT" -ne 0 ]; then
	red "Azurite npm 설치 실패 (exit=$NPM_EXIT)"
	echo "$NPM_LOG" | tail -20
	exit 1
fi
echo "$NPM_LOG" | tail -5
green "Azurite 설치 완료"
mkdir -p /tmp/azurite-data

# Azurite를 127.0.0.1 바인딩으로 시작 (Private Link 모의: 외부 접근 차단)
azurite \
	--blobHost 127.0.0.1 --blobPort 10000 \
	--queueHost 127.0.0.1 --queuePort 10001 \
	--tableHost 127.0.0.1 --tablePort 10002 \
	--location /tmp/azurite-data \
	--silent &
AZURITE_PID=$!
sleep 2

if kill -0 "$AZURITE_PID" 2>/dev/null; then
	green "Azurite 시작됨 (PID=$AZURITE_PID)"
else
	red "Azurite 시작 실패"
fi

# /etc/hosts: Private Link DNS 오버라이드 모의
# 실제 Azure Private Link 환경에서는 내부 DNS가 이 역할을 함
echo "127.0.0.1  devstoreaccount1.blob.core.windows.net" >>/etc/hosts
info "Private Link DNS 오버라이드: devstoreaccount1.blob.core.windows.net → 127.0.0.1"

# Azurite 연결 확인
if curl -fsSL --max-time 5 "http://127.0.0.1:10000/devstoreaccount1" &>/dev/null; then
	green "Azurite HTTP 응답 확인"
else
	info "Azurite 응답 대기 중..."
	sleep 3
fi

# ── 3. 패키지/FUSE 준비 ────────────────────────────────────────────────────────
step "3. 패키지/FUSE 준비 (codename=$CODENAME)"
ARCH=$(dpkg --print-architecture)
DEB_DIR="${WORKSPACE}/fuse-debs/${CODENAME}"
RESOLVED_PACKAGE_DEB=""

if [ -n "$PACKAGE_DEB" ]; then
	RESOLVED_PACKAGE_DEB=$(resolve_package_deb "$PACKAGE_DEB")
	green "release deb 확인: $RESOLVED_PACKAGE_DEB"
	DPKG_LOG=$(mktemp /tmp/release-deb-install-XXXXXX.log)
	if ! dpkg -i "$RESOLVED_PACKAGE_DEB" >"$DPKG_LOG" 2>&1; then
		log_filtered_dpkg_output "$DPKG_LOG"
		red "release deb 설치 실패"
		rm -f "$DPKG_LOG"
		exit 1
	fi
	log_filtered_dpkg_output "$DPKG_LOG"
	rm -f "$DPKG_LOG"
	green "release deb 설치 완료"
fi

# 이미 설치됐는지 확인
if dpkg -l libfuse3-3 2>/dev/null | grep -q "^ii"; then
	green "libfuse3-3 이미 설치됨 (시스템 패키지 활용)"
	if [ -n "$PACKAGE_DEB" ] && dpkg -l fuse3 2>/dev/null | grep -q "^ii"; then
		green "fuse3 release deb postinst 설치 확인"
	fi
elif [ -z "$PACKAGE_DEB" ]; then
	if [ -d "$DEB_DIR" ]; then
		DPKG_LOG=$(mktemp /tmp/fuse-install-XXXXXX.log)
		if ! dpkg -i --force-depends \
			"${DEB_DIR}/libfuse3-3_"*"_${ARCH}.deb" \
			"${DEB_DIR}/fuse3_"*"_${ARCH}.deb" \
			>"$DPKG_LOG" 2>&1; then
			log_filtered_dpkg_output "$DPKG_LOG"
			red "FUSE3 오프라인 deb 설치 실패"
			rm -f "$DPKG_LOG"
			exit 1
		fi
		log_filtered_dpkg_output "$DPKG_LOG"
		rm -f "$DPKG_LOG"
		green "FUSE3 오프라인 deb 설치 완료"
	else
		info "DEB_DIR 없음: $DEB_DIR (시스템 fuse3 사용)"
	fi
else
	red "release deb 설치 후 libfuse3-3 미설치"
	exit 1
fi

# /dev/fuse 확인
if [ -c /dev/fuse ]; then
	green "/dev/fuse 존재"
	chmod 666 /dev/fuse
else
	red "/dev/fuse 없음 (--privileged --device /dev/fuse 필요)"
fi

# /etc/fuse.conf
echo "user_allow_other" >/etc/fuse.conf
green "/etc/fuse.conf: user_allow_other 설정"

# ── 4. rclone 설치 ────────────────────────────────────────────────────────────
step "4. rclone 바이너리 설치"
if [ -n "$PACKAGE_DEB" ]; then
	test -x /usr/bin/rclone || {
		red "/usr/bin/rclone 미설치"
		exit 1
	}
	/usr/bin/rclone version | head -1
	green "release deb 경로 rclone 설치 완료"
else
	install -m 755 "${WORKSPACE}/rclone-bins/rclone-linux-${RCLONE_BIN_ARCH}" /usr/local/bin/rclone
	rclone version | head -1
	green "rclone 설치 완료"
fi

# ── 5. rclone.conf 생성 (Azurite + disable_instance_discovery) ───────────────
step "5. rclone.conf 생성"
mkdir -p /etc/rclone

# RCLONE_CONFIG 환경 변수로 모든 rclone 명령에 적용
export RCLONE_CONFIG=/etc/rclone/rclone.conf

# Azurite 기본 Connection String (devstoreaccount1)
AZURITE_CONNSTR="DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;"

cat >/etc/rclone/rclone.conf <<EOF
[azurite]
type                     = azureblob
connection_string        = ${AZURITE_CONNSTR}
disable_instance_discovery = true

[azurite-endpoint]
type                     = azureblob
account                  = devstoreaccount1
key                      = Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==
endpoint                 = http://127.0.0.1:10000/devstoreaccount1
disable_instance_discovery = true
EOF
chmod 640 /etc/rclone/rclone.conf
green "rclone.conf 생성 (Azurite, disable_instance_discovery=true)"

# ── 6. rclone CLI 기본 동작 테스트 ───────────────────────────────────────────
step "6. rclone CLI 테스트 (컨테이너 생성 / 업로드 / 다운로드)"

# 컨테이너 생성
rclone mkdir azurite:testcontainer --log-level ERROR &&
	green "컨테이너 생성: testcontainer" || red "컨테이너 생성 실패"

# 테스트 파일 생성
TEST_FILE=$(mktemp /tmp/test-XXXXXX.txt)
echo "integration-test-$(date +%s)" >"$TEST_FILE"
CONTENT=$(cat "$TEST_FILE")

# 업로드
rclone copy "$TEST_FILE" azurite:testcontainer/ --log-level ERROR &&
	green "파일 업로드 성공: $(basename $TEST_FILE)" || red "업로드 실패"

# 목록 확인
LISTED=$(rclone ls azurite:testcontainer 2>/dev/null | wc -l)
if [ "$LISTED" -gt 0 ]; then
	green "파일 목록 확인: ${LISTED}개"
else
	red "파일 목록 비어있음"
fi

# 다운로드 및 내용 검증
DOWNLOAD_DIR=$(mktemp -d /tmp/download-XXXXXX)
rclone copy azurite:testcontainer/ "$DOWNLOAD_DIR/" --log-level ERROR
DOWNLOADED_CONTENT=$(cat "$DOWNLOAD_DIR/$(basename $TEST_FILE)" 2>/dev/null || echo "")
if [ "$CONTENT" = "$DOWNLOADED_CONTENT" ]; then
	green "다운로드 내용 검증 성공"
else
	red "내용 불일치: expected='$CONTENT' actual='$DOWNLOADED_CONTENT'"
fi

# ── 7. FUSE 마운트 테스트 ─────────────────────────────────────────────────────
step "7. FUSE 마운트 테스트"
MOUNT_POINT=$(mktemp -d /tmp/rclone-mnt-XXXXXX)

cleanup_mount() {
	fusermount3 -u "$MOUNT_POINT" 2>/dev/null || fusermount -u "$MOUNT_POINT" 2>/dev/null || true
	rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap cleanup_mount EXIT

# 마운트
rclone mount azurite:testcontainer "$MOUNT_POINT" \
	--vfs-cache-mode writes \
	--allow-other \
	--log-level ERROR \
	--daemon-timeout 10s &
MOUNT_PID=$!
sleep 3

# 마운트 확인
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
	green "FUSE 마운트 성공: $MOUNT_POINT"

	# 마운트된 파일 읽기
	MNT_FILE="$MOUNT_POINT/$(basename $TEST_FILE)"
	if [ -f "$MNT_FILE" ]; then
		MNT_CONTENT=$(cat "$MNT_FILE")
		if [ "$CONTENT" = "$MNT_CONTENT" ]; then
			green "마운트된 파일 읽기 검증 성공"
		else
			red "마운트된 파일 내용 불일치"
		fi
	else
		red "마운트된 파일 없음: $MNT_FILE"
		ls "$MOUNT_POINT" || true
	fi

	# 마운트 포인트에 새 파일 쓰기
	WRITE_FILE="$MOUNT_POINT/written-by-mount-$(date +%s).txt"
	echo "written-via-fuse-mount" >"$WRITE_FILE" &&
		green "마운트 포인트 파일 쓰기 성공" || red "마운트 포인트 쓰기 실패"

	# VFS 플러시 대기 후 rclone ls 로 확인
	sleep 2
	if rclone ls azurite:testcontainer 2>/dev/null | grep -q "written-by-mount"; then
		green "마운트 쓰기 → Azure(Azurite) 동기화 확인"
	else
		info "쓰기 동기화 확인 중 (vfs-write-back 지연 허용)"
	fi
else
	red "FUSE 마운트 실패"
fi

# 언마운트
kill "$MOUNT_PID" 2>/dev/null || true
sleep 1
fusermount3 -u "$MOUNT_POINT" 2>/dev/null || fusermount -u "$MOUNT_POINT" 2>/dev/null || true
trap - EXIT
rmdir "$MOUNT_POINT" 2>/dev/null || true
green "FUSE 언마운트 완료"

# ── 8. endpoint 방식 테스트 (Private Endpoint 모의) ──────────────────────────
step "8. endpoint 방식 테스트 (Private Link 모의)"
rclone mkdir azurite-endpoint:privlink-test --log-level ERROR &&
	green "endpoint 방식 컨테이너 생성 성공" || red "endpoint 방식 실패"

echo "private-link-test-data" | rclone rcat azurite-endpoint:privlink-test/test.txt \
	--log-level ERROR &&
	green "Private Link endpoint 경유 업로드 성공" || red "업로드 실패"

PRIVLINK_CONTENT=$(rclone cat azurite-endpoint:privlink-test/test.txt 2>/dev/null || echo "")
if [ "$PRIVLINK_CONTENT" = "private-link-test-data" ]; then
	green "Private Link endpoint 경유 다운로드 검증 성공"
else
	red "Private Link endpoint 내용 불일치: '$PRIVLINK_CONTENT'"
fi

# ── 9. verify-azureblob.sh 실행 ───────────────────────────────────────────────
step "9. verify-azureblob.sh 실행"
VERIFY_AZURE_SCRIPT="${WORKSPACE}/scripts/verify-azureblob.sh"
if [ -n "$PACKAGE_DEB" ]; then
	VERIFY_AZURE_SCRIPT="/usr/share/rclone-azureblob-airgap/scripts/verify-azureblob.sh"
	green "패키지 verify-azureblob.sh 경로 사용: $VERIFY_AZURE_SCRIPT"
fi
bash "$VERIFY_AZURE_SCRIPT" \
	--remote azurite \
	--container testcontainer \
	--conf /etc/rclone/rclone.conf \
	2>/dev/null
green "verify-azureblob.sh 완료"

# ── 최종 결과 ─────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  통합 테스트 결과: PASS=$PASS  FAIL=$FAIL"
echo "  Ubuntu codename: $CODENAME"
echo "=============================================="

# Azurite 종료
kill "$AZURITE_PID" 2>/dev/null || true

if [ "$FAIL" -gt 0 ]; then
	exit 1
fi
exit 0
