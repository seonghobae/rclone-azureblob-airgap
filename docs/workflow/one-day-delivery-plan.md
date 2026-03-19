# One-Day Delivery Plan

## canonical task 선택 기준

1. 현재 브랜치/dirty tree 와 직접 연결된 이슈/PR
2. 최근 변경 파일과 가장 직접 연결된 open issue/PR
3. 그것이 없으면 전체 open issue/PR, CI, 릴리스, 문서, 배포 영향도를 기준으로 가장 먼저 닫아야 할 작업 하나

## 이 저장소의 기본 하루 전달 흐름

1. repo 사실관계 조사 (`git`, `gh`, `docs`, `workflows`, `scripts`)
2. canonical task 하나 선택
3. 테스트 먼저 추가
4. 최소 구현
5. canonical docs 동기화
6. 로컬 검증
7. push 후 GitHub Actions 확인
8. 릴리스 변경이면 태그/릴리스 검증까지 확인

## 완료 정의

- 코드, 테스트, docs, workflow, release path 가 서로 모순되지 않는다.
- 관련 GitHub Actions 가 성공한다.
- 배포/런타임 기준 문서가 실제 현재 상태를 설명한다.
