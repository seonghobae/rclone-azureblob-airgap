# rclone-azureblob-airgap

인터넷이 없는 폐쇄망(Air-gapped) Ubuntu VM에서 **rclone** 설치 및 **Azure Blob Storage FUSE mount** 환경을 완전히 구성합니다.

---

## 지원 환경

| OS | 아키텍처 | 상태 |
|----|----------|------|
| Ubuntu 22.04 LTS (Jammy) | amd64 | ✅ |
| Ubuntu 22.04 LTS (Jammy) | arm64 | ✅ |
| Ubuntu 24.04 LTS (Noble) | amd64 | ✅ |
| Ubuntu 24.04 LTS (Noble) | arm64 | ✅ |

- **rclone**: v1.73.2
- **FUSE3**: Ubuntu 22.04 3.10.5 / Ubuntu 24.04 3.14.0

---

## 설치 방법 (권장: deb 패키지)

### 1단계: 인터넷 되는 머신에서 deb 다운로드

```bash
# 최신 버전 자동 감지 다운로드 (권장)
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
LATEST=$(curl -fsSL https://api.github.com/repos/seonghobae/rclone-azureblob-airgap/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)
VER="${LATEST#v}"
curl -LO "https://github.com/seonghobae/rclone-azureblob-airgap/releases/latest/download/rclone-azureblob-airgap_${VER}_${ARCH}.deb"
curl -LO "https://github.com/seonghobae/rclone-azureblob-airgap/releases/latest/download/rclone-azureblob-airgap_${VER}_${ARCH}.deb.sha256"

# 무결성 검증
sha256sum -c "rclone-azureblob-airgap_${VER}_${ARCH}.deb.sha256"
```

또는 특정 버전을 직접 지정:

```bash
# amd64 (x86_64)
curl -LO https://github.com/seonghobae/rclone-azureblob-airgap/releases/download/v{VER}/rclone-azureblob-airgap_{VER}_amd64.deb
curl -LO https://github.com/seonghobae/rclone-azureblob-airgap/releases/download/v{VER}/rclone-azureblob-airgap_{VER}_amd64.deb.sha256
sha256sum -c rclone-azureblob-airgap_{VER}_amd64.deb.sha256

# arm64 (aarch64)
curl -LO https://github.com/seonghobae/rclone-azureblob-airgap/releases/download/v{VER}/rclone-azureblob-airgap_{VER}_arm64.deb
curl -LO https://github.com/seonghobae/rclone-azureblob-airgap/releases/download/v{VER}/rclone-azureblob-airgap_{VER}_arm64.deb.sha256
sha256sum -c rclone-azureblob-airgap_{VER}_arm64.deb.sha256
```

### 2단계: VM으로 전송

```bash
# scp 예시
scp rclone-azureblob-airgap_{VER}_{ARCH}.deb user@airgap-vm:/tmp/

# USB, rsync, 내부 파일 서버 등 어떤 방법도 가능
```

### 3단계: VM에서 설치 (한 명령으로 완료)

```bash
sudo dpkg -i rclone-azureblob-airgap_{VER}_{ARCH}.deb
```

`dpkg -i` 한 번으로 다음이 모두 자동 처리됩니다:
- ✅ `rclone` 바이너리 → `/usr/bin/rclone`
- ✅ `fusermount3` + `libfuse3.so.3` 파일 → 번들 FUSE runtime 을 오프라인 부트스트랩
- ✅ `/etc/fuse.conf` → `user_allow_other` 자동 추가
- ✅ `/etc/rclone/` 디렉토리 구조 생성
- ✅ `/etc/rclone/rclone-azureblob.conf.template` Azure 설정 템플릿 배치
- ✅ `rclone-azureblob@.service` systemd 유닛 등록

릴리스 태그 경로에서도 같은 `.deb` 에 대해 amd64/arm64 smoke-test 와, tagged `amd64`/`arm64` `.deb` 를 Docker/Azurite 경로에 다시 설치해 검증하는 Azure Blob integration workflow 가 성공한 뒤에만 GitHub Release 가 생성됩니다.

### 4단계: Azure Blob 설정

```bash
# 인터랙티브 설정 도우미 (인증 방식 선택 → conf 자동 생성)
bash /usr/share/rclone-azureblob-airgap/scripts/configure-azureblob.sh

# 또는 직접 편집
sudo vi /etc/rclone/rclone.conf
# 참고: sudo cat /etc/rclone/rclone-azureblob.conf.template
```

### 5단계: 검증

```bash
# FUSE 환경 + rclone 설치 검증
bash /usr/share/rclone-azureblob-airgap/scripts/verify-mount.sh

# Azure Blob 연결 검증 (remote 이름은 4단계에서 설정한 값)
bash /usr/share/rclone-azureblob-airgap/scripts/verify-azureblob.sh --remote <remote이름>
```

---

## deb 패키지 내용

```
/usr/bin/rclone                                             ← rclone v1.73.2 바이너리
/usr/share/rclone-azureblob-airgap/
  scripts/
    configure-azureblob.sh                                  ← Azure Blob 설정 도우미
    install.sh                                              ← 레거시 tarball 설치 도우미
    verify-azureblob.sh                                     ← Azure 연결 검증
    verify-mount.sh                                         ← FUSE mount 검증
  azure/
    rclone-azureblob.conf                                   ← 전체 인증 방식 템플릿
    conf-examples/{azblob-key,azblob-sp,azblob-msi}.conf   ← mount 설정 예시
  fuse-debs/
    jammy/{libfuse3-3,fuse3}_3.10.5-1build1_{amd64,arm64}.deb   ← 번들 오프라인 캐시
    noble/{libfuse3-3,fuse3}_3.14.0-5build1_{amd64,arm64}.deb
/lib/systemd/system/rclone-azureblob@.service              ← mount 인스턴스 유닛
/lib/systemd/system/rclone-mount@.service                  ← 범용 mount 유닛
/etc/rclone/                                                ← 설정 디렉토리 (postinst 생성)
```

---

## Azure Blob Storage mount

### 포어그라운드 테스트

```bash
mkdir -p /mnt/azureblob

rclone mount myremote:mycontainer /mnt/azureblob \
    --vfs-cache-mode writes \
    --allow-other \
    &

ls /mnt/azureblob
fusermount3 -u /mnt/azureblob
```

### systemd 영구 마운트

```bash
# 1. 마운트 설정 파일 생성
sudo mkdir -p /etc/rclone/mounts
sudo tee /etc/rclone/mounts/myblob.conf << 'EOF'
REMOTE=myremote:mycontainer
MOUNTPOINT=/mnt/azureblob
EXTRA_ARGS=--allow-other --vfs-cache-mode writes --vfs-cache-max-size 2G
EOF

# 2. 마운트 포인트 생성
sudo mkdir -p /mnt/azureblob

# 3. 서비스 시작
sudo systemctl daemon-reload
sudo systemctl start  rclone-azureblob@myblob.service
sudo systemctl enable rclone-azureblob@myblob.service

# 4. 로그 확인
sudo journalctl -u rclone-azureblob@myblob.service -f
```

---

## Azure Private Link 환경

폐쇄망에서 Azure Storage Private Endpoint 사용 시 모든 인증 설정에 아래를 추가합니다:

```ini
disable_instance_discovery = true
```

이 설정으로 rclone이 `login.microsoft.com` 메타데이터를 조회하지 않습니다.

Private Endpoint DNS 오버라이드 (내부 DNS 또는 `/etc/hosts`):
```
10.0.1.5   mystorageaccount.blob.core.windows.net
```

자세한 인증 방식별 설정은 [azure/README-azureblob.md](azure/README-azureblob.md)를 참고하세요.

---

## 대안: tarball 방식 (레거시)

deb 패키지를 사용할 수 없는 환경을 위한 대안입니다.

```bash
# 인터넷 되는 머신에서 repo clone 후 tarball 생성
git clone https://github.com/seonghobae/rclone-azureblob-airgap.git
cd rclone-azureblob-airgap
# rclone 바이너리는 .gitignore 제외 — CI 다운로드 또는 직접 추가 필요
# https://downloads.rclone.org/v1.73.2/rclone-v1.73.2-linux-amd64.zip

# VM으로 전송 후
tar -xzf rclone-airgap.tar.gz && cd rclone-airgap
sudo bash scripts/install.sh
```

---

## 트러블슈팅

### `/dev/fuse: No such file or directory`

```bash
sudo modprobe fuse
# 영구 적용
echo "fuse" | sudo tee /etc/modules-load.d/fuse.conf
```

### `user_allow_other` 오류

```bash
grep "user_allow_other" /etc/fuse.conf || echo "user_allow_other" | sudo tee -a /etc/fuse.conf
```

### 마운트 후 파일 미노출

```bash
rclone ls myremote:mycontainer    # 직접 조회 확인
# 성공 시: --dir-cache-time 5s 옵션으로 캐시 줄이기
```

### FUSE가 설치 안 됐을 때

```bash
# 번들 캐시에서 수동 설치
CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
ARCH=$(dpkg --print-architecture)
sudo dpkg -i --force-depends \
  /usr/share/rclone-azureblob-airgap/fuse-debs/${CODENAME}/libfuse3-3_*_${ARCH}.deb \
  /usr/share/rclone-azureblob-airgap/fuse-debs/${CODENAME}/fuse3_*_${ARCH}.deb
```

---

## 무결성 검증

```bash
sha256sum -c rclone-azureblob-airgap_{VER}_amd64.deb.sha256
```

---

## 라이선스

- rclone: MIT License (https://github.com/rclone/rclone/blob/master/COPYING)
- FUSE3: LGPL-2.1 (https://github.com/libfuse/libfuse)
- 패키지 스크립트: MIT License
