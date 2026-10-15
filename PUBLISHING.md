# Publishing the website and the App Store pages

## First time

```bash
git init -b main
git add -A
git commit -m "RodentLimb 1.1.2 and user manual"
gh repo create seesaw-earth/RodentLimb --public --source=. --remote=origin --push
gh api -X POST repos/seesaw-earth/RodentLimb/pages -f build_type=workflow
gh workflow run deploy.yml && gh run watch
```

Then open https://seesaw-earth.github.io/RodentLimb/ (allow a minute after the run turns green).

## Later updates

```bash
git add -A
git commit -m "Describe the change"
git push
```

Changes under `docs/` redeploy the website automatically (`.github/workflows/deploy.yml`).

## URLs for App Store Connect

| Field | English | 简体中文 |
|---|---|---|
| Support URL | https://seesaw-earth.github.io/RodentLimb/support.html | https://seesaw-earth.github.io/RodentLimb/zh/support.html |
| Marketing URL | https://seesaw-earth.github.io/RodentLimb/ | https://seesaw-earth.github.io/RodentLimb/zh/ |
| Privacy Policy URL | https://seesaw-earth.github.io/RodentLimb/privacy.html | https://seesaw-earth.github.io/RodentLimb/zh/privacy.html |

Texts for the store listing are in `AppStore/`.
