using Genius.{{SolutionName}}.AppHost;

var builder = DistributedApplication.CreateBuilder(args);

// ── Modes ────────────────────────────────────────────────────────────────────────────────────
// (unset)    Local development: the app host builds and supervises the projects from source.
// deployed   Containerized deployment: DCP owns the api and web containers, so the dashboard's
//            Resources page can start, stop, restart and stream logs for them.
// external   Containerized deployment where compose owns the containers and the app host only
//            observes them. The fallback for when DCP cannot drive the container runtime.
// dashboard  Telemetry sink only — no resource model, so the Resources page stays empty.
switch (builder.Configuration["AppHost:Mode"]?.ToLowerInvariant())
{
    case "dashboard":
        break;

    case "deployed":
        ConfigureDeployed(builder);
        break;

    case "external":
        ConfigureExternal(builder);
        break;

    default:
        ConfigureLocalDevelopment(builder);
        break;
}

await builder.Build().RunAsync().ConfigureAwait(false);

static void ConfigureLocalDevelopment(IDistributedApplicationBuilder builder)
{
    var api = builder.AddProject<Projects.WebApi>("webapi")
        .WithHttpHealthCheck("/health");

    var web = builder.AddViteApp("web", "../{{SolutionName}}.Web", "start:aspire")
        .WithPnpm()
        .WithReference(api)
        .WithEnvironment("VITE_API_URL", api.GetEndpoint("http"))
        .WithExternalHttpEndpoints()
        .WaitFor(api);

    api.WithEnvironment("Cors__Origins__0", web.GetEndpoint("http"));
}

/// <summary>
/// DCP creates and supervises the published images as sibling containers on the host's Docker daemon
/// (its socket is bind-mounted into this container). Compose only starts this app host; everything else
/// is owned here, which is what makes the Resources page controllable rather than empty.
/// </summary>
static void ConfigureDeployed(IDistributedApplicationBuilder builder)
{
    var settings = DeploymentSettings.From(builder.Configuration);

    // No "--network" runtime argument anywhere below. DCP reconciles the networks of the containers it
    // owns, and an externally supplied network makes it try to detach the container from a network it
    // has no record of, which fails the start outright with:
    //   ContainerReconciler  Could not detach network from the container ... network ... not found
    // DCP puts everything it owns on one network of its own, so {{ServicePrefix}}-web already resolves
    // {{ServicePrefix}}-api by name there. Only the hop back to this app host leaves that network, and that
    // goes over the host gateway instead.
    var api = builder.AddContainer("webapi", $"{settings.Registry}/{{ServicePrefix}}-api", settings.ImageTag)
        // The web image's nginx.conf proxies to {{ServicePrefix}}-api by name, so the container name is part
        // of the contract rather than a cosmetic choice.
        .WithContainerName("{{ServicePrefix}}-api")
        .WithImagePullPolicy(settings.ImagePullPolicy)
        // Persistent: restarting this app host must not take the application down with it.
        .WithLifetime(ContainerLifetime.Persistent)
        // No explicit host port, and the reachable publish is added as a runtime argument below.
        // DCP always publishes its own endpoints on 127.0.0.1 (DcpPublisher:BindAddress does not change
        // that), which on a server would leave the app reachable only from the machine itself.
        .WithHttpEndpoint(targetPort: DeploymentSettings.ApiContainerPort, isProxied: false)
        .WithContainerRuntimeArgs("-p", $"{settings.BindAddress}:{settings.ApiPort}:{DeploymentSettings.ApiContainerPort}")
        // Deliberately runtime arguments rather than WithBindMount. WithBindMount normalises the path
        // with the APP HOST's OS conventions, but this app host runs in a Linux container while the
        // daemon resolving the mount is the Windows host's. A "C:/..." path is not absolute to Linux, so
        // it got prefixed with the app host's working directory and the container failed to create:
        //   bind source path does not exist: /src/{{SolutionName}}.AppHost/C:/...
        // Passed as -v, the string reaches the daemon untouched.
        .WithContainerRuntimeArgs("-v", $"{settings.DataPath}:/app/Data")
        .WithContainerRuntimeArgs("-v", $"{settings.LogsPath}:/app/Logs")
        // Docker Desktop resolves host.docker.internal on its own; a plain Linux daemon does not, hence
        // the explicit host-gateway mapping. Harmless where it is already provided.
        .WithContainerRuntimeArgs("--add-host", "host.docker.internal:host-gateway")
        // Docker Desktop groups containers by these labels. Set explicitly rather than left to chance:
        // `docker compose build` bakes the BUILDING project's name into the image (the repo directory,
        // "{{ComposeProject}}"), containers inherit image labels, and the result was the app host sitting in
        // one stack while the containers it owns sat in another. Compose does not claim containers just
        // because they carry its project label, so the persistent lifetime is unaffected.
        .WithContainerRuntimeArgs("--label", $"com.docker.compose.project={settings.ComposeProject}")
        .WithContainerRuntimeArgs("--label", "com.docker.compose.service={{ServicePrefix}}-api")
        .WithEnvironment("OTEL_EXPORTER_OTLP_ENDPOINT", settings.OtlpGrpcEndpoint)
        .WithEnvironment("OTEL_EXPORTER_OTLP_PROTOCOL", "grpc")
        .WithEnvironment("OTEL_EXPORTER_OTLP_INSECURE", "true")
        // Aspire injects this for project resources but not for plain containers, and without it every
        // log line and span arrives in the dashboard under "unknown_service:dotnet" — indistinguishable
        // from anything else reporting in.
        .WithEnvironment("OTEL_SERVICE_NAME", "{{ServicePrefix}}-api");

    builder.AddContainer("web", $"{settings.Registry}/{{ServicePrefix}}-web", settings.ImageTag)
        .WithContainerName("{{ServicePrefix}}-web")
        .WithImagePullPolicy(settings.ImagePullPolicy)
        .WithLifetime(ContainerLifetime.Persistent)
        .WithHttpEndpoint(targetPort: DeploymentSettings.WebContainerPort, isProxied: false)
        .WithContainerRuntimeArgs("-p", $"{settings.BindAddress}:{settings.WebPort}:{DeploymentSettings.WebContainerPort}")
        .WithExternalHttpEndpoints()
        .WithContainerRuntimeArgs("--add-host", "host.docker.internal:host-gateway")
        .WithContainerRuntimeArgs("--label", $"com.docker.compose.project={settings.ComposeProject}")
        .WithContainerRuntimeArgs("--label", "com.docker.compose.service={{ServicePrefix}}-web")
        // nginx in this image renders its config from these at start-up. Its defaults assume every
        // container shares one network, which is true when compose owns them but not here.
        .WithEnvironment("{{EnvPrefix}}_API_UPSTREAM", settings.WebApiUpstream)
        .WithEnvironment("{{EnvPrefix}}_OTLP_UPSTREAM", settings.WebOtlpUpstream)
        .WaitFor(api);
}

/// <summary>
/// Compose owns the containers; the app host only reports them. Needs no container runtime access, so
/// it works without the Docker socket — at the cost of a read-only Resources page.
/// </summary>
static void ConfigureExternal(IDistributedApplicationBuilder builder)
{
    builder.AddExternalService("webapi", $"http://{{ServicePrefix}}-api:{DeploymentSettings.ApiContainerPort}")
        .WithHttpHealthCheck("/health");

    builder.AddExternalService("web", $"http://{{ServicePrefix}}-web:{DeploymentSettings.WebContainerPort}")
        .WithHttpHealthCheck("/");
}
