# Acceptance Criteria

## 패키지 완료 기준

### deb 패키지 설치

| 기준 | 검증 방법 |
|------|----------|
| `sudo dpkg -i *.deb` 단일 명령으로 완료 | dpkg exit 0 |
| rclone 바이너리 `/usr/bin/rclone` 설치 | `rclone version` 성공 |
| `libfuse3-3` postinst 자동 설치 | `dpkg -l libfuse3-3 \| grep '^ii'` |
| `fuse3` postinst 자동 설치 | `dpkg -l fuse3 \| grep '^ii'` |
| `/etc/fuse.conf` user_allow_other 포함 | `grep user_allow_other /etc/fuse.conf` |
| `/etc/rclone/` 디렉토리 구조 생성 | `ls /etc/rclone/` 성공 |
| systemd 유닛 등록 | `systemd-analyze verify rclone-azureblob@.service` |

### Azure Blob 연결

| 기준 | 검증 방법 |
|------|----------|
| Account Key 인증으로 컨테이너 목록 조회 | `rclone lsd remote:` |
| Connection String 인증으로 파일 업/다운 | `rclone copy` 양방향 |
| `disable_instance_discovery = true` 동작 | login.microsoft.com 없이 rclone 성공 |
| Private Endpoint DNS 경유 접속 | `/etc/hosts` 오버라이드 + rclone 성공 |

### FUSE Mount

| 기준 | 검증 방법 |
|------|----------|
| `rclone mount` 포어그라운드 성공 | 마운트 포인트 파일 접근 |
| FUSE 마운트 후 파일 읽기 | `cat <mountpoint>/<file>` 내용 일치 |
| FUSE 마운트 후 파일 쓰기 | `echo > <mountpoint>/<file>` + rclone ls 확인 |
| `fusermount3 -u` 정상 언마운트 | exit 0 |
| systemd 서비스 시작/중지 | `systemctl start/stop rclone-azureblob@*.service` |

### CI 완료 기준

| 워크플로 | 필수 통과 |
|---------|---------|
| Build deb package | amd64 + arm64 빌드 성공, amd64 + arm64 smoke-test PASS |
| Integration test | jammy + noble Docker 테스트 PASS=20 FAIL=0 |
| Private Link mock | DNS mock + Azurite endpoint + FUSE PASS |
| Release | tag 빌드한 deb를 amd64 + arm64 smoke-test 통과 후 GitHub Release 에 deb + sha256 4파일 업로드 |

## 배포 완료 기준

- GitHub Release 에 `_amd64.deb`, `_arm64.deb`, 각각의 `.sha256` 4파일 존재
- 모든 CI 워크플로 success
- README.md 설치 안내가 실제 동작과 일치
