# Xion Devnet

Xion Devnet is a multi-validator sandbox environment orchestrated with Docker Compose for local development and testing.

## Prerequisites

- [Docker](https://www.docker.com/) (version 20.10 or higher)
- [Docker Compose](https://github.com/docker/compose) (version 2.0 or higher)
- [Make](https://www.gnu.org/software/make/) (for using Makefile commands)
- [GitHub CLI](https://cli.github.com/) (`gh`) - required for building the xion image

### GitHub Container Registry Authentication

The xion node build process pulls base images from GitHub Container Registry (ghcr.io):
- `ghcr.io/goreleaser/goreleaser-cross` - for building the Go binary
- `ghcr.io/linuxcontainers/alpine` - for the runtime image

**Authenticate with Docker:**

```sh
echo "$(gh auth token)" | docker login ghcr.io --username $(gh api user --jq .login) --password-stdin
```

**Note**: The xion-explorer and xion-faucet images build from local source and only require public Docker Hub base images (no ghcr.io authentication needed)


## Quick Start

The easiest way to get started is using the provided Makefile commands:

```sh
# Build devnet images with commit ID
make build

# Start devnet in background
make start

# Stop devnet (preserves state)
make stop

# Stop and remove containers
make down

# Clean up containers
make clean

# Complete purge (removes containers and shared volume)
make purge

# Start singleton validator from .env configuration
make singleton
```

## Manual Docker Compose Commands

If you prefer to use Docker Compose directly:

```sh
# Build images with commit ID
COMMIT=$(cd ./xion && git rev-parse --short HEAD) docker compose build --pull --no-cache

# Start devnet
docker compose up -d

# Stop devnet (preserves blockchain state)
docker compose stop

# Stop and remove containers
docker compose down

# View logs
docker compose logs -f

# Complete cleanup and reset
docker compose rm -f -s -v
docker volume rm -f devnet_shared

# Restart from previous height
docker compose start
```

## Configuration Options

- **NUM_VALIDATORS**: Number of validator nodes (default: 3)
- **XIOND_VERSION**: Version tag for the xion docker image (default: latest)
- **COMMIT**: Git commit hash passed to build (automatically set by Makefile)
- **DAEMON_NAME**: Name of the daemon process (configured in .env)

## Network Information

Once running, the devnet exposes the following services through HAProxy:

- **RPC Endpoint**: `http://localhost:26657`
- **API Endpoint**: `http://localhost:1317`
- **gRPC Endpoint**: `http://localhost:9090`
- **Xion Explorer**: `http://localhost:5173`
- **Xion Faucet**: `http://localhost:3000`
- **Additional RPC**: `http://localhost:26658`

The setup includes:

- **Xion validators**: Configurable number of validator nodes (default: 3)
- **HAProxy**: Load balancer and reverse proxy
- **Xion Explorer**: Web interface for blockchain exploration
- **Xion Faucet**: Token distribution service

## Submodules

This devnet environment includes several Xion ecosystem components as git submodules:

- **[xion](https://github.com/burnt-labs/xion)** - Core Xion blockchain node and validator software
- **[xion-explorer](https://github.com/burnt-labs/xion-explorer)** - Web-based blockchain explorer for viewing transactions and blocks
- **[xion-faucet](https://github.com/burnt-labs/xion-faucet)** - Token distribution service for testnet XION tokens
- **[xion-staking](https://github.com/burnt-labs/xion-staking)** - Staking interface for validators and delegators
- **[xion-assets](https://github.com/burnt-labs/xion-assets)** - Static assets and branding resources
- **[xion-dashboard-app](https://github.com/burnt-labs/xion-dashboard-app)** - Dashboard application *(not yet available)*
- **[xion-developer-portal](https://github.com/burnt-labs/xion-developer-portal)** - Treasury contract management interface *(not yet available)*

To update all submodules to their latest commits:

```sh
git submodule update --remote --recursive
```

## Xion CLI

Assuming you have `xiond` installed locally, 

```shell
 xiond status --node http://localhost:26657/
```

or for convenience, add the following to your shell file: 

```shell
xd() {
    xiond "$@" --node http://localhost:26657/ --log_format json
}
```

And use it like so:
```shell
xd status
```




## Troubleshooting

- **Port conflicts**: Ensure ports 26657, 1317, 9090, 5173, and 3000 are available
- **Storage issues**: Use `make purge` to reset blockchain state and volumes
- **Build failures**: Try `make build` to rebuild images with commit ID
- **Permission errors**: Ensure Docker daemon is running and user has permissions
- **Service startup**: Check `docker compose logs -f` for detailed error messages
