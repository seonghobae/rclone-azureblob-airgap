# rclone Airgap Bootstrap 패키지

인터넷이 없는 폐쇄망(Air-gapped) Ubuntu VM에서 **rclone** 설치 및 **FUSE mount** 환경을 완전히 구성합니다.

---

## 지원 환경

| OS | 아키텍처 | 상태 |
|----|----------|------|
| Ubuntu 22.04 LTS (Jammy) | amd64 | ✅ 포함 |
| Ubuntu 22.04 LTS (Jammy) | arm64 | ✅ 포함 |
| Ubuntu 24.04 LTS (Noble) | amd64 | ✅ 포함 |
| Ubuntu 24.04 LTS (Noble) | arm64 | ✅ 포함 |

rclone 버전: **v1.73.2** (2025년 3월 기준 최신 stable)

---

## 패키지 구조

```
rclone-airgap/
├── README.md                    ← 이 파일
├── CHECKSUMS.sha256             ← 전체 파일 체크섬
│
├── rclone-bins/
│   ├── rclone-linux-amd64      ← rclone 바이너리 (x86_64)
│   ├── rclone-linux-arm64      ← rclone 바이너리 (aarch64)
│   ├── rclone-v1.73.2-linux-amd64.zip   ← 원본 zip (검증용)
│   ├── rclone-v1.73.2-linux-arm64.zip   ← 원본 zip (검증용)
│   └── SHA256SUMS              ← rclone 공식 체크섬
│
├── fuse-debs/
│   ├── jammy/                  ← Ubuntu 22.04용 deb
│   │   ├── libfuse3-3_3.10.5-1build1_amd64.deb
│   │   ├── fuse3_3.10.5-1build1_amd64.deb
│   │   ├── libfuse3-3_3.10.5-1build1_arm64.deb
│   │   └── fuse3_3.10.5-1build1_arm64.deb
│   └── noble/                  ← Ubuntu 24.04용 deb
│       ├── libfuse3-3_3.14.0-5build1_amd64.deb
│       ├── fuse3_3.14.0-5build1_amd64.deb
│       ├── libfuse3-3_3.14.0-5build1_arm64.deb
│       └── fuse3_3.14.0-5build1_arm64.deb
│
├── scripts/
│   ├── install.sh              ← 메인 설치 스크립트
│   └── verify-mount.sh         ← 설치 후 검증 스크립트
│
└── systemd/
    ├── rclone-mount@.service   ← systemd 인스턴스 템플릿
    └── rclone-mount-example.conf  ← 마운트 설정 예시
```

---

## 빠른 시작

### 1단계: 패키지 전송

인터넷이 되는 머신에서 tarball을 생성한 뒤 USB, scp, rsync 등으로 VM에 복사합니다.

```bash
# 패키지 생성 (인터넷 있는 머신)
tar -czf rclone-airgap.tar.gz rclone-airgap/

# VM으로 전송 (예시: scp)
scp rclone-airgap.tar.gz user@airgap-vm:/tmp/
```

### 2단계: VM에서 설치

```bash
# VM에서 실행
cd /tmp
tar -xzf rclone-airgap.tar.gz
cd rclone-airgap

# 설치 (root 필요)
sudo bash scripts/install.sh
```

### 3단계: 검증

```bash
sudo bash scripts/verify-mount.sh
```

### 4단계: rclone 설정

```bash
# 설정 편집
sudo vi /etc/rclone/rclone.conf

# 또는 인터렉티브 설정 (폐쇄망이므로 OAuth 등 불가능할 수 있음)
rclone config
```

---

## FUSE mount 사용법

### 포어그라운드 마운트 (테스트용)

```bash
mkdir -p /mnt/mydata

# S3 호환 스토리지 마운트
rclone mount myremote:mybucket /mnt/mydata \
    --vfs-cache-mode writes \
    --allow-other \
    &

# 확인
ls /mnt/mydata

# 언마운트
fusermount3 -u /mnt/mydata
```

### systemd 서비스로 영구 마운트

```bash
# 1. 마운트 설정 파일 생성
sudo mkdir -p /etc/rclone/mounts
sudo cp systemd/rclone-mount-example.conf /etc/rclone/mounts/s3data.conf
sudo vi /etc/rclone/mounts/s3data.conf
# → REMOTE, MOUNTPOINT 수정

# 2. systemd 서비스 파일 설치 (install.sh 가 이미 수행)
# /etc/systemd/system/rclone-mount@.service

# 3. 서비스 시작
sudo mkdir -p /mnt/s3data
sudo systemctl start rclone-mount@s3data.service
sudo systemctl enable rclone-mount@s3data.service

# 4. 상태 확인
sudo systemctl status rclone-mount@s3data.service
sudo journalctl -u rclone-mount@s3data.service -f
```

---

## 옵션별 설치

```bash
# rclone 바이너리만 설치 (FUSE 제외)
sudo bash scripts/install.sh --no-fuse

# 설치 경로 변경
sudo bash scripts/install.sh --prefix /usr/bin

# 설치 결과 검증만
sudo bash scripts/verify-mount.sh
```

---

## 트러블슈팅

### `/dev/fuse: No such file or directory`

```bash
# FUSE 커널 모듈 로드
sudo modprobe fuse

# 영구 적용 (재부팅 후에도)
echo "fuse" | sudo tee /etc/modules-load.d/fuse.conf

# VM인 경우: VM 설정에서 /dev/fuse passthrough 확인 필요
```

### `fusermount: option allow_other only allowed if 'user_allow_other' is set in /etc/fuse.conf`

```bash
echo "user_allow_other" | sudo tee -a /etc/fuse.conf
```

### `fuse: device not found, try 'modprobe fuse' first`

```bash
sudo modprobe fuse
# 커널에 FUSE 모듈이 없는 경우: VM 이미지에 fuse 커널 모듈이 포함됐는지 확인
lsmod | grep fuse
```

### 일반 사용자로 mount

```bash
# fuse 그룹에 사용자 추가
sudo usermod -aG fuse $USER
# 재로그인 필요
newgrp fuse

# 또는 setuid 비트 (주의: 보안 위험)
# sudo chmod u+s $(which fusermount3)
```

### VFS 캐시 관련 성능 튜닝

```bash
# 읽기 위주: minimal 캐시
rclone mount remote:/ /mnt --vfs-cache-mode minimal

# 쓰기도 함: writes 캐시 (권장)
rclone mount remote:/ /mnt --vfs-cache-mode writes

# 완전 로컬 캐시 (가장 빠르지만 디스크 소모)
rclone mount remote:/ /mnt \
    --vfs-cache-mode full \
    --vfs-cache-max-size 20G \
    --vfs-read-ahead 128M
```

---

## 무결성 검증

```bash
# 설치 전 체크섬 검증
sha256sum -c CHECKSUMS.sha256

# rclone 공식 체크섬 확인
grep "linux-amd64.zip" rclone-bins/SHA256SUMS
sha256sum rclone-bins/rclone-v1.73.2-linux-amd64.zip
```

---

## 라이선스

- rclone: MIT License (https://github.com/rclone/rclone/blob/master/COPYING)
- FUSE3: LGPL-2.1 (https://github.com/libfuse/libfuse)
- 이 패키지 스크립트: MIT License
