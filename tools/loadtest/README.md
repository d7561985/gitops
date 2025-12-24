# Connect RPC Load Tester

Simple load testing tool for Connect RPC endpoints.

## Build

```bash
go build -o loadtest .
```

## Usage

```bash
./loadtest [flags]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-url` | `https://app.demo-poc-01.work` | Base URL |
| `-rps` | `10` | Requests per second (rate limit) |
| `-c` | `5` | Number of parallel workers |
| `-d` | `30s` | Test duration |
| `-user` | `loadtest-user-1` | User ID for requests |
| `-bet` | `10.0` | Bet amount for Calculate |
| `-cpu` | `false` | Enable CPU intensive mode |

### Examples

```bash
# Quick test (5 seconds, low load)
./loadtest -d 5s -rps 5 -c 2

# Medium load test
./loadtest -d 60s -rps 50 -c 10

# Heavy load test
./loadtest -d 120s -rps 200 -c 50

# CPU intensive mode
./loadtest -d 30s -rps 20 -c 5 -cpu
```

## Endpoints

The tool tests these Connect RPC endpoints:

1. **GameEngine/Calculate** - `/api/gameconnect/game.v1.GameEngineService/Calculate`
2. **BonusService/GetProgress** - `/api/bonusconnect/wager.v1.BonusService/GetProgress`

## Output

The tool provides:
- Real-time progress bar with RPS and success/error counts
- Per-endpoint latency percentiles (p50, p90, p99, max)
- Error breakdown
- Summary statistics
