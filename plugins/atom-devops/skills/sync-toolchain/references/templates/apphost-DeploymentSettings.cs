using System.Globalization;
using Microsoft.Extensions.Configuration;

namespace Genius.{{SolutionName}}.AppHost;

/// <summary>
/// The knobs the containerized deployment needs, read from the <c>Deployment:*</c> configuration
/// section (compose passes them as <c>Deployment__Registry</c> and friends). Defaults describe the
/// standard single-host deployment, so a plain <c>docker compose up</c> needs none of them set.
/// </summary>
internal sealed record DeploymentSettings
{
    /// <summary>Port the API listens on inside its container (see {{SolutionName}}.WebApi/Dockerfile).</summary>
    public const int ApiContainerPort = {{ApiContainerPort}};

    /// <summary>Port nginx listens on inside the web container (see {{SolutionName}}.Web/nginx.conf).</summary>
    public const int WebContainerPort = {{WebContainerPort}};

    /// <summary>
    /// Compose project the managed containers report themselves as belonging to. Docker Desktop groups
    /// by this label, so it has to match the `name:` in docker-compose.yml or the app host and the
    /// containers it owns show up as two unrelated stacks.
    /// </summary>
    public required string ComposeProject { get; init; }

    public required string Registry { get; init; }

    public required string ImageTag { get; init; }

    public required string DataPath { get; init; }

    public required string LogsPath { get; init; }

    public required string OtlpGrpcEndpoint { get; init; }

    /// <summary>Upstream nginx in the web container proxies /api/ to.</summary>
    public required string WebApiUpstream { get; init; }

    /// <summary>Upstream nginx in the web container proxies /otlp/ to.</summary>
    public required string WebOtlpUpstream { get; init; }

    public required int ApiPort { get; init; }

    public required int WebPort { get; init; }

    /// <summary>
    /// How hard DCP tries to refresh the managed images.
    /// <para>
    /// Defaults to Missing, and Always is close to unusable against a private registry: DCP runs the
    /// docker CLI inside the app host container, and registry credentials are client-side
    /// (~/.docker/config.json, often behind a credential helper), not daemon-side. Mounting the socket
    /// grants the daemon, not the login — so a pull from in there is anonymous and gets
    /// "error from registry: unauthorized". The images are pulled from the host instead; see
    /// Deployment/README.md.
    /// </para>
    /// </summary>
    public required ImagePullPolicy ImagePullPolicy { get; init; }

    /// <summary>
    /// Address the published ports bind to on the host. DCP publishes its own endpoints on 127.0.0.1
    /// and offers no way to change that, so the reachable-from-the-network publish is added separately.
    /// </summary>
    public required string BindAddress { get; init; }

    public static DeploymentSettings From(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        return new DeploymentSettings
        {
            ComposeProject = Read(configuration, "ComposeProject", "{{ServicePrefix}}"),
            Registry = Read(configuration, "Registry", "ghcr.io/hwndmaster"),
            ImageTag = Read(configuration, "ImageTag", "latest"),
            DataPath = Read(configuration, "DataPath", "/data/{{ServicePrefix}}/Data"),
            LogsPath = Read(configuration, "LogsPath", "/data/{{ServicePrefix}}/Logs"),
            // Over the host gateway, not the app host's container name: DCP owns the network its
            // containers sit on, and this app host is not on it. The port is the one compose publishes.
            OtlpGrpcEndpoint = Read(configuration, "OtlpEndpoint", "http://host.docker.internal:{{OtlpGrpcPort}}"),
            // {{ServicePrefix}}-api resolves by name: DCP puts both managed containers on the same
            // network of its own.
            WebApiUpstream = Read(configuration, "WebApiUpstream",
                $"http://{{ServicePrefix}}-api:{ApiContainerPort}"),
            // The app host is NOT on that network, so this one goes back out over the host gateway to
            // the OTLP/HTTP port compose publishes.
            WebOtlpUpstream = Read(configuration, "WebOtlpUpstream", "http://host.docker.internal:{{OtlpHttpPort}}"),
            ApiPort = ReadPort(configuration, "ApiPort", {{ApiHostPort}}),
            WebPort = ReadPort(configuration, "WebPort", {{WebHostPort}}),
            ImagePullPolicy = ReadPullPolicy(configuration),
            BindAddress = Read(configuration, "BindAddress", "0.0.0.0"),
        };
    }

    // Parsed rather than switched over a hard-coded list so the setting keeps working if Aspire adds
    // policies; anything unrecognized is rejected loudly instead of silently falling back.
    private static ImagePullPolicy ReadPullPolicy(IConfiguration configuration)
    {
        var value = configuration["Deployment:ImagePullPolicy"];
        if (string.IsNullOrWhiteSpace(value))
        {
            return ImagePullPolicy.Missing;
        }

        if (!Enum.TryParse<ImagePullPolicy>(value.Trim(), ignoreCase: true, out var policy))
        {
            throw new InvalidOperationException(
                $"Deployment:ImagePullPolicy is not a known pull policy: '{value}'. "
                + $"Valid values: {string.Join(", ", Enum.GetNames<ImagePullPolicy>())}.");
        }

        return policy;
    }

    private static string Read(IConfiguration configuration, string key, string defaultValue)
    {
        var value = configuration[$"Deployment:{key}"];
        return string.IsNullOrWhiteSpace(value) ? defaultValue : value.Trim();
    }

    private static int ReadPort(IConfiguration configuration, string key, int defaultValue)
    {
        var value = configuration[$"Deployment:{key}"];
        if (string.IsNullOrWhiteSpace(value))
        {
            return defaultValue;
        }

        if (!int.TryParse(value.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
        {
            throw new InvalidOperationException(
                $"Deployment:{key} must be a port number, but was '{value}'.");
        }

        return port;
    }
}
