#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 <tool|project> <working-directory> [runtime-identifier]" >&2
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage
    exit 2
fi

restore_kind="$1"
working_directory="$2"
runtime_identifier="${3-}"

if [ "$restore_kind" != "tool" ] && [ "$restore_kind" != "project" ]; then
    usage
    exit 2
fi

if [ ! -d "$working_directory" ]; then
    echo "Working directory '$working_directory' does not exist." >&2
    exit 2
fi

secret_path="/run/secrets/atom_pkg_access_token"
if [ ! -f "$secret_path" ]; then
    echo "Secret '$secret_path' is missing." >&2
    exit 1
fi

token="$(cat "$secret_path")"
if [ -z "$token" ]; then
    echo "ATOM_PKG_ACCESS_TOKEN secret is empty." >&2
    exit 1
fi

export NuGetPackageSourceCredentials_github="Username=dummy;Password=$token"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[$timestamp] Starting dotnet $restore_kind restore in '$working_directory'."
echo "NuGet credential length: ${#token}"
echo "Dotnet SDK: $(dotnet --version)"

if command -v wget >/dev/null 2>&1; then
    if timeout 20 wget -q --spider https://nuget.pkg.github.com/hwndmaster/index.json; then
        echo "GitHub NuGet endpoint probe: OK"
    else
        echo "GitHub NuGet endpoint probe: non-success HTTP/status (often expected for unauthenticated probe)." >&2
    fi
elif command -v curl >/dev/null 2>&1; then
    if curl --silent --show-error --head --max-time 20 https://nuget.pkg.github.com/hwndmaster/index.json >/dev/null; then
        echo "GitHub NuGet endpoint probe: OK"
    else
        echo "GitHub NuGet endpoint probe: non-success HTTP/status (often expected for unauthenticated probe)." >&2
    fi
fi

cd "$working_directory"

if [ "$restore_kind" = "tool" ] && [ -n "$runtime_identifier" ]; then
    echo "Runtime identifier is only supported for project restore." >&2
    exit 2
fi

if [ "$restore_kind" = "tool" ]; then
    restore_command="dotnet tool restore --disable-parallel --verbosity minimal"
else
    if [ -n "$runtime_identifier" ]; then
        restore_command="dotnet restore --disable-parallel --verbosity minimal --runtime $runtime_identifier"
    else
        restore_command="dotnet restore --disable-parallel --verbosity minimal"
    fi
fi

if command -v timeout >/dev/null 2>&1; then
    echo "Using timeout guard for restore command (300s)."
    if timeout 300 sh -c "$restore_command"; then
        end_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "[$end_timestamp] dotnet $restore_kind restore completed."
        exit 0
    else
        exit_code="$?"
        if [ "$exit_code" -eq 124 ]; then
            echo "dotnet $restore_kind restore timed out after 300 seconds." >&2
            exit 124
        fi

        echo "dotnet $restore_kind restore failed with exit code $exit_code." >&2
        exit "$exit_code"
    fi
fi

echo "Timeout utility not available; running restore without timeout guard."
sh -c "$restore_command"
end_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[$end_timestamp] dotnet $restore_kind restore completed."
