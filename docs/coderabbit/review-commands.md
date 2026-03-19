# CodeRabbit Review Commands

## 현재 저장소 운영 현실

- 2026-03-19 기준 open/closed PR 이 없다.
- 기본 전달 흐름은 `main` 직접 push 이다.
- 따라서 CodeRabbit 명령은 feature 브랜치 + PR 을 사용할 때만 적용한다.

## 자주 쓰는 명령

PR 코멘트 또는 본문에 아래 명령을 남긴다.

```text
@coderabbitai review
@coderabbitai pause
@coderabbitai resume
@coderabbitai help
```

## 저장소 규칙

- review gate 는 dismiss 하지 않는다.
- PR 이 생기면 canonical PR 을 먼저 확인한 뒤 같은 PR 에 CodeRabbit 명령을 남긴다.
- AI review 결과가 나오면 코드/문서/테스트로 해결하고 응답한다.
