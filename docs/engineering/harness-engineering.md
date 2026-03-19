# Harness Engineering

## 목적

이 저장소의 검증 하네스는 "문서상으로 가능"이 아니라 "릴리스된 `.deb` 가 실제로 설치되고 Azure Blob/FUSE 경로가 다시 검증됨"을 보장해야 한다.

## 로컬 최소 검증

```bash
python3 -m unittest tests/test_release_hardening.py -v

python3 - <<'PY'
import pathlib, subprocess
for path in [
    pathlib.Path('.github/scripts/run-integration-test.sh'),
    pathlib.Path('.github/scripts/docker-private-link-test.sh'),
    pathlib.Path('scripts/install.sh'),
    pathlib.Path('scripts/configure-azureblob.sh'),
    pathlib.Path('scripts/verify-azureblob.sh'),
    pathlib.Path('scripts/verify-mount.sh'),
    pathlib.Path('debian/postinst'),
    pathlib.Path('debian/prerm'),
]:
    subprocess.run(['bash', '-n', str(path)], check=True)
print('bash syntax OK')
PY
```

## GitHub Actions 기준

- `Build deb package`
  - amd64/arm64 빌드
  - plain `dpkg -i` 설치 smoke-test
  - `systemd-analyze verify` 로 두 개의 systemd 템플릿 검증
  - `verify-mount.sh`, `verify-azureblob.sh` 실행
- `Integration test (Docker / Azure Private Link mock)`
  - jammy/noble Azurite E2E
  - Private Link mock (`mountpoint` + mounted read/write 검증 필수)
  - `configure-azureblob.sh` 7개 인증 방식 생성 검증
- `Release`
  - 태그 아티팩트 빌드
  - amd64/arm64 smoke-release
  - reusable integration workflow 재실행
  - 위 검증이 모두 성공할 때만 GitHub Release 생성

## 금지 사항

- 패키지 설치 smoke-test 에서 `dpkg -i --force-depends` 사용 금지
- 마운트 성공 판정에서 `ls` 를 마운트 성공 대체 신호로 사용 금지
- `dpkg -i --force-depends` 로그 필터링을 `|| true` 로 감싸 설치 실패를 숨기기 금지
- 태그 릴리스에서 mainline integration coverage 를 생략한 채 GitHub Release 생성 금지
