# PR Continuity

## 현재 상태

- open PR 이 없으면 direct-push 저장소의 정상 상태로 본다.
- closed PR / merged PR 이 존재해도 direct-push 운영과 모순되지 않는다.
- 현재 운영 방식은 `main` 직접 push + 필요 시 feature 브랜치 PR + tag release 이다.
- merged PR 이 존재하면 release tag / workflow run 과 함께 continuity evidence 로 본다.

## canonical PR 정책

- feature 브랜치를 사용할 때만 PR 을 만든다.
- 같은 목적의 PR 이 여러 개 생기면 가장 최신 CI 상태와 최신 head 를 가진 PR 을 canonical PR 로 본다.
- 다른 PR 은 duplicate 또는 stacked follow-up 으로 정리한다.
- release 실패를 고친 follow-up PR 은 직전 실패 tag/run 과 함께 continuity evidence 로 기록한다.

## 점검 명령

```bash
python3 "$HOME/.config/opencode/scripts/pr_continuity.py" --json --limit 50
gh pr list --state all --limit 50
```

## direct-push 저장소에서의 해석

- PR continuity 결과가 비어 있으면 정상이다.
- direct push 를 썼더라도 release 태그와 workflow run 이 continuity evidence 역할을 한다.
