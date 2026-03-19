# PR Continuity

## 현재 상태

- 2026-03-19 기준 `seonghobae/rclone-azureblob-airgap` 에 open PR 이 없다.
- closed PR 도 없다.
- 현재 운영 방식은 `main` 직접 push + tag release 이다.

## canonical PR 정책

- feature 브랜치를 사용할 때만 PR 을 만든다.
- 같은 목적의 PR 이 여러 개 생기면 가장 최신 CI 상태와 최신 head 를 가진 PR 을 canonical PR 로 본다.
- 다른 PR 은 duplicate 또는 stacked follow-up 으로 정리한다.

## 점검 명령

```bash
python3 "$HOME/.config/opencode/scripts/pr_continuity.py" --json --limit 50
gh pr list --state all --limit 50
```

## direct-push 저장소에서의 해석

- PR continuity 결과가 비어 있으면 정상이다.
- direct push 를 썼더라도 release 태그와 workflow run 이 continuity evidence 역할을 한다.
