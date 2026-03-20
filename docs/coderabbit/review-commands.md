# CodeRabbit Review Commands

## 현재 저장소 운영 현실

- 기본 전달 흐름은 `main` 직접 push 이다.
- feature 브랜치 PR 은 release/runtime 회귀나 큰 리팩터링처럼 review gate 가 필요한 작업에 사용한다.
- CodeRabbit 명령은 PR 을 만들었을 때만 적용한다.
- merged PR 이 있어도 direct-push 운영과 모순되지 않으며, 다음 feature PR 도 같은 canonical PR 규칙을 따른다.

## 자주 쓰는 명령

PR 상태를 다시 확인할 때는 아래 명령으로 현재 repo 상태를 먼저 본다.

```bash
gh pr list --state all --limit 50
```

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
