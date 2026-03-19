# AGENTS.md

## Repository 개요

`rclone-azureblob-airgap` — 폐쇄망 Ubuntu VM용 rclone + Azure Blob Storage FUSE mount 부트스트랩 패키지.

## 빌드/테스트 명령

```bash
# deb 빌드 (로컬, fakeroot 필요)
fakeroot dpkg-buildpackage -b -us -uc

# 설치 검증 (로컬, Ubuntu 환경 필요)
sudo dpkg -i --force-depends ../rclone-azureblob-airgap_*.deb
sudo bash /usr/share/rclone-azureblob-airgap/scripts/verify-mount.sh

# Azure 연결 검증
bash /usr/share/rclone-azureblob-airgap/scripts/verify-azureblob.sh --remote <이름>

# CI 트리거 (GitHub Actions)
git push  # Build deb + Integration test 자동 실행
```

## 코드 스타일

- Shell 스크립트: `set -euo pipefail`, 함수 단위 분리, `info/ok/warn/fail` 출력 헬퍼 사용
- `((VAR++))` 금지: `set -e` 에서 VAR=0 시 exit 1 발생 → `VAR=$((VAR + 1))` 사용
- `bash -c "$(cat script)"` 금지: 특수문자 확장 문제 → 파일 직접 실행
- Dockerfile heredoc 내 `[section]` 금지: Dockerfile 명령어로 파싱됨 → `printf '%s\n'` 사용

## 환경 변수 주의사항

- `RCLONE_VERSION` 환경변수 사용 금지: rclone이 `--version` 플래그로 해석 → `RCLONE_VER` 사용

## 파일 구조 (핵심)

```
debian/
  control    — 패키지 메타데이터 (Depends: ${misc:Depends} 만, Recommends 없음)
  postinst   — FUSE3 자동 설치 + /etc/rclone 뼈대 생성
  rules      — dh_strip/shlibdeps/makeshlibs override (Go 바이너리)
  changelog  — 버전: 1.73.2-{N}
fuse-debs/   — 번들 FUSE3 오프라인 캐시 (git 추적됨)
rclone-bins/ — 바이너리 (.gitignore, CI에서 다운로드)
.github/
  workflows/
    build-deb.yml        — PR/push 시 빌드 + smoke-test
    integration-test.yml — Docker + Azurite E2E
    release.yml          — tag v* → GitHub Release
  scripts/
    run-integration-test.sh      — Docker 내 실행
    docker-private-link-test.sh  — Private Link 모의 테스트
  docker/
    Dockerfile.private-link      — Private Link 모의 이미지
```

## deb 빌드 시 주의

- `DEB_HOST_ARCH` 로 대상 아키텍처 판별 (크로스빌드 시 `dpkg --print-architecture` 사용 금지)
- `/usr/local/bin` 에 바이너리 설치 금지 (dh_usrlocal 차단) → `/usr/bin` 사용
- `dh_makeshlibs`, `dh_strip`, `dh_shlibdeps` 모두 override (Go 정적 바이너리)

## PR/이슈 정책

- 새 기능: `feat:` 커밋 메시지
- 버그 수정: `fix:` 커밋 메시지
- 문서 갱신: `docs:` 커밋 메시지
- 릴리즈: `git tag v{rclone_ver}-{pkg_rev}` → push → Release 워크플로 자동 실행

## 테스트 범위

| 테스트 | 검증 항목 |
|--------|----------|
| Build deb smoke-test | amd64+arm64 실제 설치, FUSE3 자동 설치, /etc/rclone 레이아웃, systemd 유닛, bundled examples/fuse-debs 검증 |
| Docker integration (jammy/noble) | Azurite + rclone CLI + FUSE mount + verify-azureblob.sh |
| Private Link mock | DNS 오버라이드, disable_instance_discovery, Azurite endpoint |
| configure-azureblob.sh | 비인터랙티브 7개 인증 방식(Account Key, SAS, ConnStr, SP Secret/Cert, MSI System/User, env_auth) 생성 |
