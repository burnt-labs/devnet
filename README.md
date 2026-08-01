# Xion Devnet — Full Stack

Run the entire Xion ecosystem locally with Docker Compose.

## Quick Start

```bash
git clone --recurse-submodules -b chore/devnet-v28 https://github.com/burnt-labs/devnet.git
cd devnet
cp .env.example .env
make core          # chain + haproxy + explorer + faucet
make full          # everything
```

## Profiles

| Profile | Services |
|---------|----------|
| `core` | Xion (3 validators), HAProxy, Explorer, Faucet |
| `apps` | Core + AA API, Dashboard, Staking, Dev Portal, Indexer, Assets |
| `oauth` | Apps + OAuth3, OAuth2 API, OAuth2 Clients Dashboard |
| `zk` | Apps + ZK Email Backend, Prover, Worker |
| `ibc` | Core + Osmosis, Noble, Hermes relayer |
| `full` | Everything |

## Ports

| Port | Service | Port | Service |
|------|---------|------|---------|
| 1317 | Xion REST | 8001 | Indexer Proxy |
| 9090 | Xion gRPC | 8002 | OAuth2 API |
| 26657 | Xion RPC | 8003 | OAuth2 Clients |
| 3000 | Faucet | 8080 | OAuth3 |
| 3001 | AA API | 8081 | ZK Email Prover |
| 3002 | Indexer GraphQL | 8082 | ZK Email Worker |
| 3003 | Developer Portal | 8788 | Staking |
| 3004 | Assets | 26757 | Osmosis RPC |
| 4173 | Dashboard | 26857 | Noble RPC |
| 5173 | Explorer | 9190/9290 | Osmosis/Noble gRPC |
| 8444 | HAProxy Stats | 26656 | Xion P2P |

## Commands

```bash
make build PROFILE=apps    # Build images
make start PROFILE=apps    # Start
make logs PROFILE=apps     # Follow logs
make status                # Container status
make purge                 # Remove everything
```

## IBC

The `ibc` profile starts Osmosis (v28.0.0) and Noble (v11.3.0) with a Hermes relayer (v1.12.0). Channels are auto-created for `transfer` on both pairs. Noble includes USDC minting via `fiat-tokenfactory`.

## Environment

See `.env.example` for all variables. Key ones: `XIOND_VERSION`, `NUM_VALIDATORS`, `RELAYER_MNEMONIC`, `STYTCH_PUBLIC_TOKEN`, `FEE_GRANTER_ADDRESS`.
