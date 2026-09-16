# {{SolutionName}} server deployment

Runs the published images on a server, with a **working Aspire Resources page** — not just the
telemetry tabs.

## Why this is not just a compose file

The Aspire dashboard's Resources page is fed by the app host's resource service. An app host started in
`dashboard` mode builds no resource model, so that page is empty and only Structured logs / Traces /
Metrics work. To get resources you can actually see and control, the app host has to *own* them.

So this stack starts exactly **one** compose service — the app host — and mounts the host's Docker
socket into it. The app host's DCP orchestrator then creates `{{ServicePrefix}}-api` and `{{ServicePrefix}}-web`
itself, as siblings on the same daemon. The dashboard gets start/stop/restart, console logs, endpoints
and health for both.

```
compose ──starts──> {{ServicePrefix}}-apphost ──DCP via /var/run/docker.sock──> {{ServicePrefix}}-api
                                                                       └──> {{ServicePrefix}}-web
```

### What this costs

- **The socket mount is root-equivalent.** A container that can drive the Docker daemon can do anything
  on the host. Acceptable on a single-tenant machine running only images you built; not on a shared or
  internet-exposed host.
- **The app host is a development-time tool by design.** Microsoft does not support it as a production
  host. An Aspire upgrade can change orchestration behaviour, and that is yours to fix.

If either is unacceptable, use `external` mode (below). You keep the Resources page with live health;
you lose lifecycle control.

## Prerequisites

- Docker Engine with compose v2, logged in to the registry so **you** can pull the images:
  ```shell
  echo <ghp_token> | docker login ghcr.io -u hwndmaster --password-stdin
  ```
- Images published by `publish-docker.ps1` at the repo root.
- `Deployment/.env`, copied from `.env.example` and filled in.

## Run

```shell
docker compose --env-file .env up -d
```

| URL | What |
|-----|------|
| <http://localhost:{{DashboardPort}}> | Aspire dashboard — Resources, Structured logs, Traces, Metrics |
| <http://localhost:{{WebHostPort}}> | The SPA |
| <http://localhost:{{ApiHostPort}}> | The API |

The dashboard asks for a login token on first open; it is printed in the app host's log
(`docker logs {{ServicePrefix}}-apphost`). See `{{EnvPrefix}}_DASHBOARD_ANONYMOUS` in `.env.example` for
turning that off on a trusted network.

Updating to newly published images:

```powershell
.\update.ps1
```

Add `-SkipPull` to recreate the containers from images already on the machine, which is what you want
after building locally — pulling there would replace your build with the published one.

The script exists because the order matters and two of the steps are not obvious:

```powershell
docker compose --env-file .env --profile pull pull   # 1. pull from the HOST, not the app host
docker compose --env-file .env down                  # 2. the app host must be DOWN for step 3
docker rm -f {{ServicePrefix}}-api {{ServicePrefix}}-web     # 3. forces a recreate; "No such container" on a
                                                     #    first run is expected, not a failure
docker compose --env-file .env up -d                 # 4. recreates both from the pulled images
```

- **Step 3 is not optional.** The api and web containers are `ContainerLifetime.Persistent`, so they
  survive an app host restart by design — and DCP *adopts* an existing container on start-up without
  ever re-examining its image. Pull and `up -d` on their own leave the previous build running while the
  dashboard reports everything Running and healthy, so the update silently does nothing.
- **Step 2 has to come before step 3.** DCP builds its resource model at start-up and does not reconcile
  a container that disappears underneath it: remove them while the app host is running and they simply
  stay gone until it is restarted.

### Why the images are pulled from the host, and not by the app host

Registry credentials are **client-side**. `docker login` writes them to `~/.docker/config.json`, often
behind a credential helper (`credsStore: desktop` on Docker Desktop). Mounting `/var/run/docker.sock`
into the app host grants it the *daemon*, not the *login* — the docker CLI in that container has no
config and no helper, so anything it pulls goes out anonymous and a private registry answers:

```
Error response from daemon: error from registry: unauthorized
```

That is why `Deployment__ImagePullPolicy` defaults to `Missing` and the api/web images are declared in
`docker-compose.yml` under the `pull` profile: `--profile pull pull` fetches them from the host with the
login you already have, `up` never starts them, and the app host then finds them present. Setting the
policy to `Always` puts the pull back inside the container and breaks against a private registry.

## Switching to `external` mode (the fallback)

If DCP cannot drive the container runtime on this host, no rebuild is needed — it is configuration:

1. `AppHost__Mode: external` in `docker-compose.yml`
2. Remove the `/var/run/docker.sock` volume from the app host service
3. Delete the two `profiles: ["pull"]` lines, so compose starts those services instead of only pulling
   them — they are already defined in full for exactly this

Compose owns the containers again, and the app host reports them via `AddExternalService` — name, URL
and live health on the Resources page, with the Structured logs / Traces / Metrics tabs unchanged.

## Paths are host paths

`{{EnvPrefix}}_DATA_PATH` and `{{EnvPrefix}}_LOGS_PATH` are passed to the **host's** Docker daemon when
it creates the api container, so they resolve against the host filesystem — not against anything inside
the app host container.

They are also passed as raw `-v` container runtime arguments rather than through Aspire's `WithBindMount`.
`WithBindMount` normalises the path using the **app host's** OS conventions, and the app host here is a
Linux container while the daemon resolving the mount is the Windows host's. A `C:/...` path is not
absolute to Linux, so it was treated as relative and the container refused to be created:

```
invalid mount config for type "bind": bind source path does not exist:
  /src/{{SolutionName}}.AppHost/C:/Users/.../Data
```

As `-v` the string reaches the daemon untouched. The trade-off is that these mounts do not appear in the
dashboard's Volumes panel, because Aspire has no model of them.

## Troubleshooting

**Resources page is empty.** The app host is in `dashboard` mode, or `AppHost__Mode` never reached it.
Check `docker exec {{ServicePrefix}}-apphost printenv AppHost__Mode`.

**App host logs a container runtime error on start.** It cannot reach the daemon. Confirm the socket is
mounted (`docker exec {{ServicePrefix}}-apphost docker info`) — the image ships the `docker` CLI precisely
so this is checkable from inside.

**The SPA loads but API calls 502.** nginx in the web image proxies `/api/` to whatever
`{{EnvPrefix}}_API_UPSTREAM` names, which defaults to `{{ServicePrefix}}-api:{{ApiContainerPort}}`. In `deployed` mode both
managed containers sit on DCP's own network and resolve each other by name, so this should just work;
check `docker network inspect` on the `aspire-persistent-network-*` network to confirm both are attached.

**Telemetry from the browser stops arriving.** The `/otlp/` proxy is the only hop that leaves DCP's
network, so it goes over `host.docker.internal` to the published OTLP/HTTP port. Override it with
`{{EnvPrefix}}_OTLP_UPSTREAM` if the host gateway is not reachable under that name. This failure is
deliberately non-fatal: nginx resolves the upstream per request, so the SPA keeps working and only
telemetry is lost.

## Ports are published twice, on purpose

`docker ps` shows two publishes per managed container, for example:

```
{{ServicePrefix}}-api   127.0.0.1:{{ApiContainerPort}}->{{ApiContainerPort}}/tcp, 0.0.0.0:{{ApiHostPort}}->{{ApiContainerPort}}/tcp
```

The loopback one is DCP's own; it always publishes on `127.0.0.1` and there is no setting that changes
that (`DcpPublisher:BindAddress` governs DCP's proxy listeners, not this). On a server that alone would
leave the app reachable only from the machine itself, so the app host adds the second, reachable publish
as an explicit container runtime argument. `{{EnvPrefix}}_BIND_ADDRESS` controls its address; set it to
`127.0.0.1` if you want the app reachable only locally.

A consequence: the URLs shown on the Resources page are DCP's loopback ones (`http://localhost:{{ApiContainerPort}}`),
not the published ones. They work from the server itself; from another machine use the ports above.

## Networking, and why there is no shared network setting

An earlier version passed `--network <compose network>` to the managed containers so they could reach
the app host by its compose name. **That does not work.** DCP reconciles the networks of containers it
owns, and an externally supplied network makes it try to detach the container from a network it has no
record of; the container is created and then never started:

```
ContainerReconciler  Could not detach network from the container
  NetworkID: {{ServicePrefix}}_default
  error: network {{ServicePrefix}}_default not found
```

So the managed containers stay on DCP's network, which is enough for web → api, and the one hop that
must leave it (web → app host, for browser telemetry) goes over the host gateway instead.
