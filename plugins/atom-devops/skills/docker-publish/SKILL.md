---
name: docker-publish
description: Build, tag and push a Genius/Atom app's Docker images to ghcr.io, and prune old package versions afterwards. Use when asked to publish the docker images, push to ghcr, release the app, build and push the containers, clean up old package versions, or when publish-docker.ps1 or packages-cleanup.ps1 fails on tokens, scopes or a Docker daemon that is not reachable.
---

# Publish Docker images

Two scripts at the repo root, run in this order. Both are managed by `sync-toolchain` — if either
needs a change, change the template, not the repo copy.

## Preconditions

Check these **before** running anything; every one of them is a failure the script reports late.

| Requirement | Why | How to satisfy |
|-------------|-----|----------------|
| `GITHUB_REGISTRY_TOKEN` | logging in to `ghcr.io` to push | env var, or pass `-RegistryToken` / `-GithubToken` |
| `ATOM_PKG_ACCESS_TOKEN` | the compose build secret that lets the Dockerfiles restore the private `Genius.*` packages | env var, or pass `-AtomPkgAccessToken` |
| Docker Desktop running, Linux containers | the images are Linux | the script auto-starts Docker Desktop and waits `-DockerReadyTimeoutSeconds` (default 60); pass `-NoAutoStartDockerDesktop` to opt out |
| Docker Compose **v2** | the script drives `docker compose` | ships with Docker Desktop |
| `gh` authenticated with `read:packages` and `delete:packages` | cleanup calls the GitHub packages API | `gh auth refresh -h github.com -s read:packages,delete:packages` |

The token is piped to `docker login --password-stdin` — never put it on the command line.

## Publish

```powershell
./publish-docker.ps1
```

Useful parameters: `-DockerUser` (default `hwndmaster`), `-Registry` (default `ghcr.io`),
`-DockerReadyTimeoutSeconds`, `-NoAutoStartDockerDesktop`.

What it does, as discrete steps that abort the run on the first non-zero exit:

1. logs in to the registry;
2. builds the two compose services — **api, then web**, with `COMPOSE_PARALLEL_LIMIT=1` so the
   private-package restore is not hammered concurrently;
3. tags each built image (`<compose-project>-<service>`) as
   `<registry>/<user>/<service>:latest`;
4. pushes both.

It restores any previous `ATOM_PKG_ACCESS_TOKEN` and `COMPOSE_PARALLEL_LIMIT` in a `finally` block, so
an interrupted run does not leave the environment mutated.

The apps publish no app host image. On the server one shared app host
([hwndmaster/app-host](https://github.com/hwndmaster/app-host), with its own publish script) runs every
app; after publishing, the app's `Deployment/update.ps1` on the server pulls the new images.

## Clean up old versions

```powershell
./packages-cleanup.ps1 -DryRun
```

Always dry-run first and read what it would delete. Then run it without `-DryRun`.

It walks each package in the `$Packages` list, keeps every version carrying the `latest` tag, and
deletes the rest. Two safety behaviours worth knowing:

- if a package has **no** `latest` tag, it skips that package entirely rather than deleting anything;
- a failure on one version or one package is reported and the run continues to the next.

`$Packages` defaults to the three published images. It is a parameter, so a one-off prune of a single
package is `-Packages @("<prefix>-api")`.

## Failure modes

- **"Registry token is required" / "Package token is required"** — the corresponding env var is unset.
  These are checked before Docker is touched.
- **"Docker daemon is not reachable"** after the timeout — Docker Desktop did not come up, or it is in
  Windows-containers mode. Switch it to Linux containers.
- **A build step fails on restoring `Genius.*` packages** — `ATOM_PKG_ACCESS_TOKEN` is set but not
  valid for the package registry. The secret reaches the build through the compose `secrets:` block,
  so also confirm the Dockerfile still consumes `atom_pkg_access_token`.
- **"Missing required gh token scopes"** — run the `gh auth refresh` line the script prints.
- **A tag step fails with "No such image"** — the built image name is
  `<compose-project>-<service>`, where the compose project is the repo directory name. If the
  directory was renamed, the tags in `publish-docker.ps1` no longer match; fix the
  `ComposeProject` token and re-render via `sync-toolchain` rather than editing the script.
