# Architecture

## 개요

`rclone-azureblob-airgap` 은 인터넷이 없는 Ubuntu VM에서
rclone + FUSE3 + Azure Blob Storage mount 환경을 **단일 deb 패키지**
또는 **tarball** 방식으로 완전히 부트스트랩합니다.

---

## 배포 레이어

```text
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Release (인터넷 되는 머신에서 다운로드)                  │
│  rclone-azureblob-airgap_{VER}_{amd64,arm64}.deb                │
│  (예: v{rclone_ver}-{pkg_rev})                                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │ scp / USB / 내부 파일 서버
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Airgapped Ubuntu VM                                            │
│  sudo dpkg -i rclone-azureblob-airgap_{VER}_{ARCH}.deb          │
│                                                                 │
│  postinst configure:                                            │
│  ① install_fuse3_offline()   — 번들 fuse-debs 자동 dpkg -i     │
│  ② fuse 그룹 생성                                               │
│  ③ /etc/fuse.conf user_allow_other                              │
│  ④ /etc/rclone/{rclone.conf, azure-env.conf, ...} 뼈대 생성    │
│  ⑤ rclone-azureblob.conf.template 배치                          │
│  ⑥ systemd daemon-reload                                        │
│  ⑦ /usr/local/bin/rclone → /usr/bin/rclone 심볼릭 링크         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 파일 배치 (deb 설치 후)

| 경로 | 역할 |
|------|------|
| `/usr/bin/rclone` | rclone 바이너리 (Go 정적 바이너리) |
| `/usr/local/bin/rclone` | 심볼릭 링크 → `/usr/bin/rclone` |
| `/usr/share/rclone-azureblob-airgap/scripts/` | 설치/검증 스크립트 |
| `/usr/share/rclone-azureblob-airgap/azure/` | rclone.conf 템플릿, mount conf 예시 |
| `/usr/share/rclone-azureblob-airgap/fuse-debs/` | 번들 오프라인 FUSE3 deb 캐시 |
| `/lib/systemd/system/rclone-azureblob@.service` | Azure Blob mount 인스턴스 유닛 |
| `/lib/systemd/system/rclone-mount@.service` | 범용 mount 인스턴스 유닛 |
| `/etc/rclone/rclone.conf` | rclone remote 설정 (postinst 뼈대 생성) |
| `/etc/rclone/azure-env.conf` | env_auth 방식 환경변수 파일 |
| `/etc/rclone/rclone-azureblob.conf.template` | 전체 인증 방식 주석 템플릿 |
| `/etc/rclone/mounts/` | systemd 인스턴스별 mount 설정 디렉토리 |
| `/etc/rclone/certs/` | SP 인증서 배치 위치 (chmod 700) |

---

## tarball 방식 (레거시 / deb 불가 환경)

```text
rclone-airgap/          ← repo 루트 (git clone 또는 tarball)
├── rclone-bins/        ← rclone 바이너리 (.gitignore, CI에서 다운로드)
│   └── rclone-linux-{amd64,arm64}
├── fuse-debs/          ← FUSE3 오프라인 deb 캐시 (git에 포함)
├── scripts/
│   ├── install.sh      ← tarball 설치 진입점 (PKG_ROOT 기반)
│   ├── configure-azureblob.sh
│   ├── verify-azureblob.sh
│   └── verify-mount.sh
├── azure/              ← Azure Blob 설정 템플릿
├── systemd/            ← systemd 유닛 파일
└── debian/             ← deb 패키지 메타데이터
```

`scripts/install.sh` 는 `PKG_ROOT=$(dirname SCRIPT_DIR)` 로 자신이 실행된
위치를 기준으로 동작합니다.  
deb 설치 후에는 `PKG_ROOT=/usr/share/rclone-azureblob-airgap` 이 됩니다.

---

## FUSE3 번들 전략

| 구성 요소 | 버전 | 대상 OS |
|-----------|------|---------|
| `libfuse3-3` | 3.10.5-1build1 | Ubuntu 22.04 (jammy) |
| `fuse3` | 3.10.5-1build1 | Ubuntu 22.04 (jammy) |
| `libfuse3-3` | 3.14.0-5build1 | Ubuntu 24.04 (noble) |
| `fuse3` | 3.14.0-5build1 | Ubuntu 24.04 (noble) |

각 amd64/arm64 조합 = 총 8개 deb 파일이 패키지에 포함됩니다.  
`postinst` 는 실행 시 `/etc/os-release` + `dpkg --print-architecture` 로 정확한 파일을 선택합니다.

---

## Azure Private Link 대응

```text
Azure VM (폐쇄망)
  │
  │ /etc/hosts 또는 내부 DNS
  │ mystorageaccount.blob.core.windows.net → 10.0.1.5 (Private Endpoint IP)
  │
  └─► rclone (disable_instance_discovery=true)
        └─► Private Endpoint → Azure Storage Account
              (login.microsoft.com 접근 없음)
```

`disable_instance_discovery = true` 는 `azure/rclone-azureblob.conf` 모든 섹션에 기본 포함됩니다.

---

## CI/CD 파이프라인

```text
push/PR → main
  ├── Build deb package
  │     ├── Download rclone {amd64,arm64}  (병렬)
  │     ├── Build deb {amd64,arm64}        (병렬)
  │     └── Smoke test {amd64,arm64}
  │           ├── dpkg -i (postinst 검증)
  │           ├── bundled FUSE runtime bootstrap 검증
  │           ├── bundled fuse-debs(8 files) assertion
  │           ├── example conf 존재 assertion
  │           └── verify-mount.sh, verify-azureblob.sh (--allow-missing-fuse)
  │
  └── Integration test (Docker)
        ├── Docker integration {jammy,noble} x {amd64,arm64}  (병렬)
        │     Azurite + FUSE + rclone E2E
        ├── Private Link DNS mock test {amd64,arm64}
        │     DNS override + `mountpoint` + mounted read/write
        └── configure-azureblob.sh 비인터랙티브 테스트

push → tag v*
  └── Release
        ├── Build release deb {amd64,arm64}
        ├── Smoke release {amd64,arm64}
        │     ├── plain dpkg -i on tagged artifact
        │     ├── FUSE3 runtime bootstrap verification
        │     ├── systemd-analyze verify
        │     └── verify-mount.sh, verify-azureblob.sh (--allow-missing-fuse)
        ├── Reusable Integration test workflow
        │     ├── Docker integration {jammy,noble} x {amd64,arm64}
        │     │     tagged `amd64`/`arm64` deb install + packaged verify path
        │     ├── Private Link DNS mock test {amd64,arm64}
        │     │     DNS override + `mountpoint` + mounted read/write
        │     └── configure-azureblob.sh 비인터랙티브 테스트
        └── Create GitHub Release (only after smoke-release + integration success)
```

---

## systemd mount 템플릿 인자 전달 규칙

- `systemd/rclone-azureblob@.service`, `systemd/rclone-mount@.service` 는
  `/etc/rclone/mounts/%i.conf` 의 `REMOTE`, `MOUNTPOINT`, `EXTRA_ARGS`
  를 사용한다.
- `REMOTE`, `MOUNTPOINT` 는 단일 인자로 유지되어야 하므로
  `${REMOTE} ${MOUNTPOINT}` 형태를 유지한다.
- `EXTRA_ARGS` 는 `--allow-other --read-only` 처럼 공백으로 구분된
  **여러 rclone 플래그** 를 담으므로 `ExecStart=` 에서 반드시
  `$EXTRA_ARGS` 로 전달한다.
- `${EXTRA_ARGS:-}` 같은 shell 기본값 확장은 systemd `ExecStart=`
  문법이 아니므로 사용하면 mount 실행 시 rclone 이 usage 를 출력하고
  종료할 수 있다.

---

## 인증 방식 결정 트리 (폐쇄망 기준)

```text
인터넷 완전 차단?
  YES → Account Key / Connection String / SAS URL 중 선택
         (AAD 토큰 교환 불필요)
  NO  →
    Azure VM + Managed Identity 있음?
      YES → MSI (use_msi = true)
      NO  → Service Principal + Private Link for AAD
```

---

## 확장/업그레이드

### rclone 버전 업그레이드

1. `.github/workflows/build-deb.yml`, `integration-test.yml`, `release.yml`
   의 `RCLONE_VER` 변경
2. `debian/control` Description 버전 갱신
3. `debian/changelog` 항목 추가
4. 태그 → Release 자동 생성

### FUSE3 버전 업그레이드

1. Ubuntu 패키지 미러에서 신규 deb 다운로드
2. `fuse-debs/{jammy,noble}/` 교체
3. `debian/rules` 의 deb 파일명 패턴 확인 (와일드카드 사용 중 — 자동 대응)
