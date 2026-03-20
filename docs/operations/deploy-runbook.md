# Deploy Runbook

## 배포 전 체크리스트

- [ ] `git log --oneline -5` — 최근 커밋 확인
- [ ] GitHub Actions 모든 워크플로 green (`gh run list --limit 5`)
- [ ] `debian/changelog` 버전 항목 추가됨
- [ ] `README.md` 설치 안내와 검증 경로가 현재 패키지/릴리스 동작과 일치
- [ ] Release workflow 가 tagged `amd64`/`arm64` `.deb` 설치형 integration coverage 까지 통과함
- [ ] `tests/test_release_hardening.py` 통과

## 배포 실행

```bash
# 1. 태그 생성 및 push
git tag v1.73.2-{N}
git push origin v1.73.2-{N}

# 2. Release 워크플로 확인
gh run list --repo seonghobae/rclone-azureblob-airgap --limit 3

# 3. Release 결과물 확인
gh release view v1.73.2-{N} --repo seonghobae/rclone-azureblob-airgap
```

## 배포 후 검증 (폐쇄망 VM)

```bash
# VM에서 실행
ARCH=$(dpkg --print-architecture)
sudo dpkg -i rclone-azureblob-airgap_1.73.2-{N}_${ARCH}.deb

# rclone 버전 확인
rclone version

# FUSE 확인
dpkg -l libfuse3-3 fuse3 | grep '^ii'
ls /dev/fuse && echo "/dev/fuse OK"

# release gating 참고: GitHub Actions 에서 amd64/arm64 모두 dpkg -i + smoke-test 통과 후 릴리스됨

# Azure Blob 연결 확인
bash /usr/share/rclone-azureblob-airgap/scripts/verify-azureblob.sh --remote <remote>

# FUSE mount 확인
bash /usr/share/rclone-azureblob-airgap/scripts/verify-mount.sh
```

## 롤백

```bash
# 이전 버전 deb 재설치 (다운그레이드)
sudo dpkg -i --force-downgrade rclone-azureblob-airgap_1.73.2-{PREV}_{ARCH}.deb
```

## 트러블슈팅: FUSE 미설치 상태

postinst가 완전히 실행되지 않았을 때:

```bash
CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
ARCH=$(dpkg --print-architecture)
CACHE=/usr/share/rclone-azureblob-airgap/fuse-debs/${CODENAME}

sudo dpkg -i --force-depends \
  ${CACHE}/libfuse3-3_*_${ARCH}.deb \
  ${CACHE}/fuse3_*_${ARCH}.deb

sudo modprobe fuse
sudo chmod 666 /dev/fuse
```

## 트러블슈팅: systemd 서비스 미등록

```bash
sudo systemctl daemon-reload
sudo systemctl list-unit-files | grep rclone
systemd-analyze verify /lib/systemd/system/rclone-azureblob@.service /lib/systemd/system/rclone-mount@.service
```
