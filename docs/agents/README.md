# Agents README

## 기본 원칙

- 이 저장소는 repo-first 문서를 우선한다.
- 실제 코드/워크플로 변경 전에는 관련 canonical docs 를 먼저 확인한다.
- 변경이 구조/동작/검증 흐름에 영향을 주면 `AGENTS.md`, `ARCHITECTURE.md`, 관련 `docs/**` 를 같이 갱신한다.

## 권장 skill / subagent 사용

- 계획 수립: `writing-plans`
- 구현: `subagent-driven-development`
- 버그/회귀 수정: `test-driven-development`
- 완료 전 검증: `verification-before-completion`
- PR 정리: `pr-continuity`

## 저장소별 실행 규칙

- 기본 브랜치: `main`
- 기본 전달 흐름: 단일 메인테이너 환경에서는 `main` 직접 push 허용
- feature 브랜치를 사용할 때만 PR 생성/정리 수행
- 태그 릴리스는 `v{rclone_ver}-{pkg_rev}` 형식

## 최소 완료 체크

- `tests/test_release_hardening.py` 통과
- 변경된 Bash 스크립트 `bash -n` 통과
- `gh run list --limit 5` 에서 관련 워크플로 성공 확인
- 릴리스 변경이면 tagged release workflow 와 latest release artifact 까지 재확인
