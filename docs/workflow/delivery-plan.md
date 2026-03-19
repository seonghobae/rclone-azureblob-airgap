# Delivery Plan

## 릴리즈 사이클

```
1. 기능 구현 / 버그 수정 → main 브랜치 push
2. CI 자동 실행 (Build deb + Integration test)
3. CI green 확인
4. git tag v{rclone_ver}-{pkg_rev}  (예: v1.73.2-3)
5. git push origin v{rclone_ver}-{pkg_rev}
6. Release 워크플로 자동 실행 → GitHub Release 생성
7. 사용자: GitHub Release 에서 deb 다운로드 → VM 전송 → dpkg -i
```

## 버전 체계

- `{rclone_ver}`: rclone upstream 버전 (예: 1.73.2)
- `{pkg_rev}`: 패키지 개정번호 (1부터 증가)
- 태그 형식: `v{rclone_ver}-{pkg_rev}` (예: `v1.73.2-2`)
- deb 버전: `{rclone_ver}-{pkg_rev}` (예: `1.73.2-2`)

## PR 흐름

모든 변경은 main 브랜치에 직접 push (단일 메인테이너 환경).  
변경 규모가 클 때는 feature 브랜치 → PR → CI 확인 → merge.

## rclone 버전 업그레이드 절차

1. 새 rclone 버전 확인: https://downloads.rclone.org/
2. 워크플로 `RCLONE_VER` 값 갱신 (build-deb.yml, integration-test.yml, release.yml)
3. `debian/changelog` 새 항목 추가
4. `debian/control` Description 버전 갱신
5. CI 통과 확인
6. 새 태그 push → Release

## FUSE3 패키지 업그레이드 절차

1. Ubuntu 공식 미러에서 신규 버전 deb 다운로드
   ```bash
   # jammy amd64 예시
   curl -O http://mirrors.kernel.org/ubuntu/pool/main/f/fuse3/fuse3_{NEW_VER}_amd64.deb
   curl -O http://mirrors.kernel.org/ubuntu/pool/main/f/fuse3/libfuse3-3_{NEW_VER}_amd64.deb
   # arm64: http://ports.ubuntu.com/ubuntu-ports/pool/main/f/fuse3/
   ```
2. `fuse-debs/{jammy,noble}/` 교체
3. `debian/rules` 의 하드코딩 버전 문자열 갱신 (없으면 와일드카드 이미 사용 중)
4. CI 통과 확인 → 릴리즈

## 폐쇄망 VM 업그레이드 절차

```bash
# 1. 인터넷 되는 머신에서 새 deb 다운로드
curl -LO https://github.com/seonghobae/rclone-azureblob-airgap/releases/latest/download/rclone-azureblob-airgap_NEW_amd64.deb

# 2. VM으로 전송 후
sudo dpkg -i rclone-azureblob-airgap_NEW_amd64.deb
# dpkg가 기존 패키지를 자동 업그레이드 처리
```
