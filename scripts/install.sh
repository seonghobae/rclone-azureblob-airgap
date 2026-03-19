#!/usr/bin/env bash
# =============================================================================
# rclone Airgap Bootstrap Installer
# 인터넷이 없는 Ubuntu VM에서 rclone + FUSE3 mount 환경을 완전히 셋업합니다.
#
# 지원 대상:
#   - Ubuntu 22.04 LTS (Jammy Jellyfish)  amd64 / arm64
#   - Ubuntu 24.04 LTS (Noble Numbat)     amd64 / arm64
#
# 사용법:
#   sudo bash install.sh [옵션]
#
# 옵션:
#   --no-fuse        FUSE/mount 패키지 설치 건너뜀 (rclone 바이너리만 설치)
#   --prefix DIR     rclone 설치 경로 (기본값: /usr/local/bin)
#   --man            man page 설치
#   --check          설치 후 검증만 실행 (설치 건너뜀)
#   -h, --help       이 도움말 출력
# =============================================================================
set -euo pipefail

# ── 색상 출력 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ── 기본값 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(dirname "$SCRIPT_DIR")"   # rclone-airgap/ 루트
INSTALL_PREFIX="/usr/local/bin"
INSTALL_MAN=false
SKIP_FUSE=false
CHECK_ONLY=false

# ── 인수 파싱 ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-fuse)    SKIP_FUSE=true ;;
    --prefix)     INSTALL_PREFIX="$2"; shift ;;
    --man)        INSTALL_MAN=true ;;
    --check)      CHECK_ONLY=true ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) warn "알 수 없는 옵션: $1" ;;
  esac
  shift
done

# ── root 권한 확인 ────────────────────────────────────────────────────────────
if [[ "$CHECK_ONLY" == false ]] && [[ $EUID -ne 0 ]]; then
  fail "설치에는 root 권한이 필요합니다. sudo bash $0 을 사용하세요."
fi

echo ""
echo "=================================================="
echo "  rclone Airgap Bootstrap Installer"
echo "  패키지 루트: $PKG_ROOT"
echo "=================================================="
echo ""

# ── 검증만 실행 ───────────────────────────────────────────────────────────────
if [[ "$CHECK_ONLY" == true ]]; then
  info "== 설치 검증 모드 =="
  if command -v rclone &>/dev/null; then
    ok "rclone 발견: $(rclone version 2>/dev/null | head -1)"
  else
    fail "rclone 이 PATH에 없습니다."
  fi

  if [[ -f /usr/local/bin/rclone ]] || [[ -f /usr/bin/rclone ]]; then
    ok "rclone 바이너리 위치 확인됨"
  fi

  if modinfo fuse &>/dev/null 2>&1 || modinfo fuse3 &>/dev/null 2>&1; then
    ok "FUSE 커널 모듈 사용 가능"
  else
    warn "FUSE 커널 모듈을 확인할 수 없습니다 (VM 환경에서 정상일 수 있음)"
  fi

  if dpkg -l libfuse3-3 &>/dev/null 2>&1 | grep -q "^ii"; then
    ok "libfuse3-3 패키지 설치됨"
  else
    warn "libfuse3-3 가 dpkg에 등록되지 않음 (--no-fuse 모드였을 수 있음)"
  fi

  info "rclone version:"
  rclone version 2>/dev/null || true
  exit 0
fi

# ── OS / 아키텍처 감지 ────────────────────────────────────────────────────────
detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    fail "/etc/os-release 를 찾을 수 없습니다. Ubuntu 22.04/24.04 이 필요합니다."
  fi
  source /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_CODENAME:-unknown}"
  info "OS 감지: $PRETTY_NAME"

  case "$OS_VERSION" in
    jammy)  UBUNTU_CODENAME="jammy" ;;
    noble)  UBUNTU_CODENAME="noble" ;;
    *)
      warn "Ubuntu $OS_VERSION 은 공식 테스트 대상이 아닙니다."
      # 버전 번호로 폴백 추론
      case "${VERSION_ID:-}" in
        22.*) UBUNTU_CODENAME="jammy" ;;
        24.*) UBUNTU_CODENAME="noble" ;;
        *)    fail "지원하지 않는 Ubuntu 버전: ${VERSION_ID:-unknown}. jammy(22.04) 또는 noble(24.04) 이 필요합니다." ;;
      esac
      warn "폴백으로 $UBUNTU_CODENAME 패키지를 사용합니다."
      ;;
  esac
}

detect_arch() {
  MACHINE="$(uname -m)"
  case "$MACHINE" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)             fail "지원하지 않는 아키텍처: $MACHINE. amd64/arm64 이 필요합니다." ;;
  esac
  info "아키텍처: $ARCH"
}

detect_os
detect_arch

# ── rclone 바이너리 설치 ──────────────────────────────────────────────────────
install_rclone() {
  local bin_src="$PKG_ROOT/rclone-bins/rclone-linux-${ARCH}"
  if [[ ! -f "$bin_src" ]]; then
    fail "rclone 바이너리를 찾을 수 없습니다: $bin_src"
  fi

  info "rclone 바이너리 설치: $bin_src → $INSTALL_PREFIX/rclone"
  install -m 755 -o root -g root "$bin_src" "$INSTALL_PREFIX/rclone"

  # 심볼릭 링크 /usr/bin 에도 생성 (선택)
  if [[ "$INSTALL_PREFIX" != "/usr/bin" ]] && [[ ! -f /usr/bin/rclone ]]; then
    ln -sf "$INSTALL_PREFIX/rclone" /usr/bin/rclone || true
  fi

  ok "rclone 설치 완료: $("$INSTALL_PREFIX/rclone" version 2>/dev/null | head -1)"
}

# ── man page 설치 ─────────────────────────────────────────────────────────────
install_man() {
  if [[ "$INSTALL_MAN" == true ]]; then
    local man_src="$PKG_ROOT/rclone-bins/rclone.1"
    if [[ -f "$man_src" ]]; then
      install -D -m 644 "$man_src" /usr/local/share/man/man1/rclone.1
      mandb -q 2>/dev/null || true
      ok "man page 설치 완료"
    else
      warn "rclone.1 man page 파일 없음 (건너뜀)"
    fi
  fi
}

# ── FUSE3 패키지 설치 ─────────────────────────────────────────────────────────
install_fuse() {
  if [[ "$SKIP_FUSE" == true ]]; then
    warn "FUSE 설치 건너뜀 (--no-fuse 옵션)"
    return
  fi

  local deb_dir="$PKG_ROOT/fuse-debs/$UBUNTU_CODENAME"
  if [[ ! -d "$deb_dir" ]]; then
    fail "FUSE deb 패키지 디렉토리가 없습니다: $deb_dir"
  fi

  # 이미 설치됐는지 확인
  if dpkg -l libfuse3-3 2>/dev/null | grep -q "^ii"; then
    ok "libfuse3-3 이미 설치됨, 건너뜀"
    return
  fi

  info "FUSE3 패키지 오프라인 설치 중... (codename=$UBUNTU_CODENAME, arch=$ARCH)"

  # 의존성 순서: libfuse3-3 먼저, fuse3 나중
  local pkgs_ordered=()
  local libpkg deb_path

  # libfuse3-3 (공유 라이브러리) - 먼저
  libpkg=$(find "$deb_dir" -name "libfuse3-3_*_${ARCH}.deb" | head -1)
  if [[ -n "$libpkg" ]]; then
    pkgs_ordered+=("$libpkg")
  else
    warn "libfuse3-3_*_${ARCH}.deb 를 $deb_dir 에서 찾지 못함"
  fi

  # fuse3 (CLI + udev rules) - 나중
  deb_path=$(find "$deb_dir" -name "fuse3_*_${ARCH}.deb" | head -1)
  if [[ -n "$deb_path" ]]; then
    pkgs_ordered+=("$deb_path")
  else
    warn "fuse3_*_${ARCH}.deb 를 $deb_dir 에서 찾지 못함"
  fi

  if [[ ${#pkgs_ordered[@]} -eq 0 ]]; then
    fail "$deb_dir 에서 ${ARCH} 용 deb 파일을 전혀 찾지 못했습니다."
  fi

  # dpkg --force-depends 로 의존성 미충족 경고를 억제하며 설치
  # (인터넷 없이 apt 의존성 해결 불가 환경 대응)
  dpkg -i --force-depends "${pkgs_ordered[@]}" 2>&1 | grep -v "^(Reading\|Selecting\|Preparing\|Unpacking\|Setting up\|Processing)" || true

  # udev 규칙 적용 (fuse3 패키지가 설치하는 /etc/udev/rules.d/99-fuse3.rules)
  if command -v udevadm &>/dev/null; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
  fi

  # fuse 그룹 설정
  if getent group fuse &>/dev/null; then
    info "fuse 그룹 존재 확인됨"
  else
    groupadd fuse 2>/dev/null || true
    info "fuse 그룹 생성"
  fi

  # /dev/fuse 권한 확인
  if [[ -c /dev/fuse ]]; then
    ok "/dev/fuse 장치 존재"
    chmod 666 /dev/fuse 2>/dev/null || true
  else
    warn "/dev/fuse 가 없습니다. 커널에서 FUSE가 활성화되지 않았을 수 있습니다."
    warn "  → VM이면: modprobe fuse 를 시도하거나, VM 설정에서 /dev/fuse를 passthrough하세요."
  fi

  ok "FUSE3 패키지 설치 완료"
}

# ── /etc/fuse.conf 설정 (user_allow_other) ────────────────────────────────────
configure_fuse_conf() {
  if [[ "$SKIP_FUSE" == true ]]; then return; fi

  if [[ ! -f /etc/fuse.conf ]]; then
    cat > /etc/fuse.conf << 'EOF'
# /etc/fuse.conf - rclone airgap 부트스트랩으로 생성
#
# user_allow_other 를 활성화하면 -o allow_other 마운트 옵션 사용 가능
# (다른 사용자도 마운트 포인트에 접근 가능)
user_allow_other
EOF
    ok "/etc/fuse.conf 생성 완료"
  else
    if ! grep -q "^user_allow_other" /etc/fuse.conf; then
      echo "user_allow_other" >> /etc/fuse.conf
      ok "/etc/fuse.conf 에 user_allow_other 추가"
    else
      ok "/etc/fuse.conf 이미 user_allow_other 포함"
    fi
  fi
}

# ── rclone 설정 디렉토리 준비 ─────────────────────────────────────────────────
setup_rclone_config() {
  local cfg_dir="/etc/rclone"
  if [[ ! -d "$cfg_dir" ]]; then
    mkdir -p "$cfg_dir"
    chmod 750 "$cfg_dir"
    info "rclone 전역 설정 디렉토리 생성: $cfg_dir"
  fi

  if [[ ! -f "$cfg_dir/rclone.conf" ]]; then
    cat > "$cfg_dir/rclone.conf" << 'EOF'
# rclone 설정 파일
# rclone config 명령어로 remote를 추가하세요.
# 문서: https://rclone.org/docs/
#
# 예시 (S3 호환):
# [myremote]
# type = s3
# provider = Minio
# endpoint = http://minio.internal:9000
# access_key_id = ACCESSKEY
# secret_access_key = SECRETKEY
# region = us-east-1
EOF
    chmod 640 "$cfg_dir/rclone.conf"
    ok "rclone 설정 파일 템플릿 생성: $cfg_dir/rclone.conf"
  fi
}

# ── systemd 서비스 파일 복사 ──────────────────────────────────────────────────
install_systemd_templates() {
  local svc_dir="$PKG_ROOT/systemd"
  if [[ ! -d "$svc_dir" ]]; then
    warn "systemd 템플릿 디렉토리 없음: $svc_dir (건너뜀)"
    return
  fi

  info "systemd 서비스 템플릿 설치..."
  for f in "$svc_dir"/*.service "$svc_dir"/*.mount 2>/dev/null; do
    [[ -f "$f" ]] || continue
    local dest="/etc/systemd/system/$(basename "$f")"
    install -m 644 "$f" "$dest"
    info "  설치됨: $dest"
  done
  systemctl daemon-reload 2>/dev/null || true
  ok "systemd 템플릿 설치 완료"
}

# ── Azure Blob 관련 파일 배포 ─────────────────────────────────────────────────
install_azure_assets() {
  local az_dir="$PKG_ROOT/azure"
  if [[ ! -d "$az_dir" ]]; then
    warn "azure 디렉토리 없음: $az_dir (건너뜀)"
    return
  fi

  info "Azure Blob 설정 파일 배포..."

  # rclone.conf 에 Azure Blob 템플릿 병합 (아직 azureblob 섹션 없을 때만)
  if ! grep -q "type.*=.*azureblob" /etc/rclone/rclone.conf 2>/dev/null; then
    {
      echo ""
      echo "# ── Azure Blob Storage (주석 처리된 템플릿) ──────────────"
      echo "# bash scripts/configure-azureblob.sh 로 설정하거나"
      echo "# azure/rclone-azureblob.conf 를 참고해 직접 편집하세요."
    } >> /etc/rclone/rclone.conf
    ok "Azure Blob 안내 주석 추가됨: /etc/rclone/rclone.conf"
  fi

  # mount 설정 예시 파일 복사
  local mnt_conf_dir="/etc/rclone/mounts"
  mkdir -p "$mnt_conf_dir"
  for f in "$az_dir/conf-examples/"*.conf; do
    [[ -f "$f" ]] || continue
    local dest="$mnt_conf_dir/$(basename "$f").example"
    install -m 640 "$f" "$dest"
    info "  예시 conf: $dest"
  done

  # Azure rclone.conf 템플릿 (전체 주석 버전)
  install -m 640 "$az_dir/rclone-azureblob.conf" /etc/rclone/rclone-azureblob.conf.template
  ok "Azure Blob 전체 템플릿: /etc/rclone/rclone-azureblob.conf.template"

  # 인증서 디렉토리 준비 (SP 인증서 방식용)
  mkdir -p /etc/rclone/certs
  chmod 700 /etc/rclone/certs
  ok "인증서 디렉토리: /etc/rclone/certs (chmod 700)"

  # azure-env.conf 뼈대 생성 (env_auth 환경 변수 파일)
  if [[ ! -f /etc/rclone/azure-env.conf ]]; then
    install -m 600 /dev/null /etc/rclone/azure-env.conf
    cat > /etc/rclone/azure-env.conf << 'EOF'
# Azure 인증 환경 변수 파일 (env_auth 방식용)
# systemd 서비스가 EnvironmentFile 로 이 파일을 읽습니다.
# 사용 전 실제 값으로 교체하세요.

# Service Principal 인증
# AZURE_TENANT_ID=<TenantID-GUID>
# AZURE_CLIENT_ID=<ClientID-GUID>
# AZURE_CLIENT_SECRET=<ClientSecret>

# Storage Account 이름 (env_auth 에서 읽음)
# AZURE_STORAGE_ACCOUNT_NAME=<스토리지계정이름>

# 인증서 기반 SP 인증
# AZURE_CLIENT_CERTIFICATE_PATH=/etc/rclone/certs/sp-cert.pem
# AZURE_CLIENT_CERTIFICATE_PASSWORD=<암호>
EOF
    ok "Azure 환경 변수 파일 생성: /etc/rclone/azure-env.conf (chmod 600)"
  fi
}

# ── 설치 요약 ─────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo "=================================================="
  echo "  설치 완료 요약"
  echo "=================================================="
  echo ""
  echo "  rclone 위치  : $INSTALL_PREFIX/rclone"
  rclone version 2>/dev/null | head -1 | sed 's/^/  버전       : /'
  echo ""
  if [[ "$SKIP_FUSE" == false ]]; then
    echo "  FUSE3 라이브러리: $(dpkg -l libfuse3-3 2>/dev/null | awk '/^ii/{print $3}' || echo 'N/A')"
    echo "  fuse3 패키지   : $(dpkg -l fuse3 2>/dev/null | awk '/^ii/{print $3}' || echo 'N/A')"
  fi
  echo ""
  echo "  ─── Azure Blob Storage 설정 순서 ──────────────"
  echo "  # 1단계: 인터랙티브 설정 도우미"
  echo "  bash scripts/configure-azureblob.sh"
  echo ""
  echo "  # 또는 수동 편집"
  echo "  vi /etc/rclone/rclone.conf"
  echo "  # (참고 템플릿: /etc/rclone/rclone-azureblob.conf.template)"
  echo ""
  echo "  # 2단계: 연결 검증"
  echo "  bash scripts/verify-azureblob.sh --remote <이름>"
  echo ""
  echo "  # 3단계: 포어그라운드 마운트 테스트"
  echo "  mkdir -p /mnt/azureblob"
  echo "  rclone mount <remote>:<container> /mnt/azureblob --vfs-cache-mode writes &"
  echo ""
  echo "  # 4단계: systemd 영구 마운트"
  echo "  vi /etc/rclone/mounts/<이름>.conf   # REMOTE, MOUNTPOINT 설정"
  echo "  systemctl start  rclone-azureblob@<이름>.service"
  echo "  systemctl enable rclone-azureblob@<이름>.service"
  echo ""
  echo "  ─── 검증 명령어 ────────────────────────────────"
  echo "  bash scripts/verify-mount.sh"
  echo "  bash scripts/verify-azureblob.sh --remote <이름> --container <컨테이너>"
  echo "=================================================="
}

# ── 메인 실행 흐름 ────────────────────────────────────────────────────────────
info "단계 1/5: rclone 바이너리 설치"
install_rclone

info "단계 2/5: man page 설치"
install_man

info "단계 3/5: FUSE3 패키지 설치"
install_fuse

info "단계 4/5: FUSE 설정"
configure_fuse_conf

info "단계 5/6: rclone 설정 및 systemd 템플릿"
setup_rclone_config
install_systemd_templates

info "단계 6/6: Azure Blob 설정 파일 배포"
install_azure_assets

print_summary
