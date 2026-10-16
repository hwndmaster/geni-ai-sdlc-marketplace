# {{SolutionName}} on the server

{{SolutionName}} runs under the shared **app host** ([hwndmaster/app-host](https://github.com/hwndmaster/app-host)),
which creates and supervises its containers and shows them, with their logs, traces and metrics, on its
dashboard. This folder goes to `C:\Docker\{{SolutionName}}` on the server, next to `C:\Docker\app-host`;
the data and logs folders sit inside it by default.

| File | What it is |
|------|------------|
| `app.json` | How the app host runs {{SolutionName}}: ports, mounts, memory limits |
| `.env.example` | Copy to `.env`: this server's data and logs paths, and optional ports, limits and image tag |
| `docker-compose.yml` | Names the two images so `update.ps1` can pull them. It starts nothing |
| `update.ps1` | Installs or updates {{SolutionName}}. The other applications keep running |

## Install

1. Install the app host first (its `Deployment\README.md`).
2. Copy this folder to `C:\Docker\{{SolutionName}}`, then:
   ```powershell
   Copy-Item .env.example .env   # and fill it in
   ```
   Create the data and logs folders it names.
3. Register {{SolutionName}} in `C:\Docker\app-host\apps.json` by its folder inside the apps root,
   `C:\Docker` (use whatever the folder is called):
   ```json
   { "path": "{{SolutionName}}" }
   ```
4. Run `.\update.ps1`. The first run is the installation.

## Update

```powershell
.\update.ps1              # after publishing new images
.\update.ps1 -SkipPull    # after changing app.json or .env, or after a local build
```

It pulls the images, stops the app host, removes `{{ServicePrefix}}-api` and `{{ServicePrefix}}-web`, and
starts the app host again, which recreates them. Only {{SolutionName}} is down meanwhile, usually for
under a minute; the dashboard is unavailable for about 20 seconds.

Removing the containers is the step that matters. On start-up the app host attaches to the containers it
finds without checking which image they run, so pulling and restarting alone would leave the old version
running while the dashboard reports it healthy.

## When something is wrong

- **`update.ps1` times out.** Open the dashboard's Resources page. {{SolutionName}} shows there with
  "Configuration error" and the reason when its `app.json` or `.env` is wrong, and is missing entirely
  when `apps.json` does not register it.
- **A container keeps restarting.** `docker inspect {{ServicePrefix}}-api --format "{{.State.OOMKilled}}"`;
  if `true`, raise its memory limit in `.env` and run `.\update.ps1 -SkipPull`.
