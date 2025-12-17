# Proto/gRPC Code Generation Infrastructure

This document describes the infrastructure for automatic gRPC code generation from proto files with publication to GitLab.

## Architecture Overview

```
gitlab.com/gitops-poc-dzha/
└── api/
    ├── ci/                           # CI/CD Components (reusable pipelines)
    │   └── templates/proto-gen/      # Proto generation component
    ├── proto/                        # Proto definitions (source of truth)
    │   ├── user-service/             # Repository with .proto files
    │   ├── payment-service/
    │   └── game-engine/
    └── gen/                          # Generated code (auto-managed by CI)
        └── {service-name}/           # Sub-group (auto-created)
            ├── go/                   # Repository: Go module
            ├── nodejs/               # Repository: npm package
            ├── php/                  # Repository: Composer package
            ├── python/               # Repository: pip package
            └── angular/              # Repository: gRPC-Web for browsers
```

Each language gets its own **repository**, which ensures:
- Clean `go get` without hacks (Go modules work natively)
- Clear versioning per language repository
- Simple package manager integration

## Tools Used

- **Buf CLI** - Modern protocol buffer tooling (linting, breaking change detection, code generation)
- **GitLab CI/CD Components** - Reusable pipeline configuration ([api/ci](https://gitlab.com/gitops-poc-dzha/api/ci))
- **GitLab API** - Automatic sub-group and repository creation

## Versioning Strategy (GitFlow)

| Branch | Version Format | Example | Description |
|--------|----------------|---------|-------------|
| dev | v0.0.0-{short-sha} | v0.0.0-abc1234 | Development snapshots |
| main + tag | v{major}.{minor}.{patch} | v1.2.3 | Stable releases |

All languages receive the same version for a given proto change, ensuring consistency across polyglot microservices.

---

## Generated Repository Structure

When CI pipeline runs, it creates a sub-group `gen/{service-name}/` with separate repositories for each language:

```
gen/my-service/                        # Sub-group (auto-created)
├── go/                                # Repository
│   ├── README.md
│   ├── go.mod                         # module gitlab.com/.../gen/my-service/go
│   └── myservice/v1/
│       ├── myservice.pb.go            # Message types
│       └── myservice_grpc.pb.go       # gRPC client/server stubs
├── nodejs/                            # Repository
│   ├── README.md
│   ├── package.json                   # @gitops-poc-dzha/my-service
│   └── myservice/v1/
│       └── myservice.ts               # protobuf-ts generated code
├── php/                               # Repository
│   ├── README.md
│   ├── composer.json                  # gitops-poc-dzha/my-service
│   └── Myservice/V1/
│       ├── MyserviceServiceClient.php
│       └── GetSomethingRequest.php
├── python/                            # Repository
│   ├── README.md
│   ├── pyproject.toml                 # gitops-poc-dzha-my-service
│   ├── __init__.py
│   └── myservice/v1/
│       ├── __init__.py
│       ├── myservice_pb2.py           # Message types
│       └── myservice_pb2_grpc.py      # gRPC stubs
└── angular/                           # Repository
    ├── README.md
    ├── package.json                   # @gitops-poc-dzha/my-service-web
    └── myservice/v1/
        └── MyserviceServiceClientPb.ts
```

### Package Names by Language

| Language | Package Path | Install Command |
|----------|--------------|-----------------|
| Go | `gitlab.com/gitops-poc-dzha/api/gen/my-service/go` | `go get gitlab.com/.../go@v1.2.3` |
| Node.js | `@gitops-poc-dzha/my-service` | `npm install git+https://gitlab.com/.../nodejs.git#v1.2.3` |
| PHP | `gitops-poc-dzha/my-service` | composer (vcs repository) |
| Python | `gitops-poc-dzha-my-service` | `pip install git+https://gitlab.com/.../python.git@v1.2.3` |
| Angular | `@gitops-poc-dzha/my-service-web` | `npm install git+https://gitlab.com/.../angular.git#v1.2.3` |

---

## Quick Start: Creating a New Proto Service (Zero-Config!)

### Step 1: Create Service Directory

```bash
mkdir -p my-service/proto/myservice/v1
cd my-service
```

### Step 2: Add CI Configuration

Just one file with 3 lines:

```yaml
# .gitlab-ci.yml
include:
  - project: 'gitops-poc-dzha/api/ci'
    file: '/templates/proto-gen/template.yml'
```

**That's it!** No `buf.yaml` or `buf.gen.yaml` needed - they are auto-generated from `$CI_PROJECT_NAME`.

### Step 3: Create Your Proto File

```protobuf
// proto/myservice/v1/service.proto
syntax = "proto3";

package myservice.v1;

service MyService {
  rpc GetItem(GetItemRequest) returns (GetItemResponse);
}

message GetItemRequest { string id = 1; }
message GetItemResponse { string id = 1; string name = 2; }
```

### Step 4: Push and Done!

```bash
git init && git add . && git commit -m "Initial proto"
git remote add origin https://gitlab.com/gitops-poc-dzha/api/proto/my-service.git
git push -u origin main
```

CI will automatically generate code for Go, Node.js, PHP, Python, and Angular.

### Optional: Customize Generation

Override defaults in your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'gitops-poc-dzha/api/ci'
    file: '/templates/proto-gen/template.yml'

variables:
  PROTO_GEN_LANGUAGES: "go,nodejs"  # Only these languages
  BUF_VERSION: "1.48.0"             # Specific Buf version
```

**Available variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PROTO_GEN_LANGUAGES` | `go,nodejs,php,python,angular` | Languages to generate |
| `BUF_VERSION` | `1.47.2` | Buf CLI version |
| `DEFAULT_BRANCH` | `main` | Branch for breaking change detection |

**Example - generate only Go and Node.js:**
```yaml
include:
  - project: 'gitops-poc-dzha/api/ci'
    file: '/templates/proto-gen/template.yml'

variables:
  PROTO_GEN_LANGUAGES: "go,nodejs"
```

---

## Using Generated Packages

### Go

**Настройка для приватных репозиториев:**

```bash
# Установите переменные окружения
export GOPRIVATE=gitlab.com/gitops-poc-dzha/*
export GONOSUMDB=gitlab.com/gitops-poc-dzha/*
export GONOPROXY=gitlab.com/gitops-poc-dzha/*

# Создайте ~/.netrc с токеном (требуется scope read_api!)
echo "machine gitlab.com login YOUR_USERNAME password YOUR_GITLAB_TOKEN" > ~/.netrc
chmod 600 ~/.netrc

# Теперь можно устанавливать модули
go get gitlab.com/gitops-poc-dzha/api/gen/my-service/go@v1.2.3
```

> **Важно:** Токен должен иметь scope `read_api`, а не только `read_repository`.
> Это необходимо для корректной работы go-import meta tags.

**go.mod example:**
```go
module my-app

go 1.22

require (
    gitlab.com/gitops-poc-dzha/api/gen/my-service/go v1.2.3
)
```

**Dockerfile для CI/CD:**

При сборке Docker образов с приватными зависимостями используйте `.netrc`:

```dockerfile
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates

ARG GITLAB_TOKEN
RUN if [ -n "$GITLAB_TOKEN" ]; then \
    echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
    chmod 600 ~/.netrc; \
    fi

ENV GOPRIVATE=gitlab.com/gitops-poc-dzha/*
ENV GONOSUMDB=gitlab.com/gitops-poc-dzha/*
ENV GONOPROXY=gitlab.com/gitops-poc-dzha/*

SHELL ["/bin/ash", "-c"]

COPY go.mod go.sum ./
RUN go mod download
# ...
```

В CI передавайте токен: `docker build --build-arg GITLAB_TOKEN=${CI_PUSH_TOKEN} .`

**Usage:**
```go
package main

import (
    "context"
    "log"

    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"

    // Import generated package - path matches proto package structure
    myservicev1 "gitlab.com/gitops-poc-dzha/api/gen/my-service/go/myservice/v1"
)

func main() {
    conn, err := grpc.Dial("localhost:9090", grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        log.Fatal(err)
    }
    defer conn.Close()

    // Create client from generated code
    client := myservicev1.NewMyServiceClient(conn)

    // Make RPC call
    resp, err := client.GetSomething(context.Background(), &myservicev1.GetSomethingRequest{
        Id: "123",
    })
    if err != nil {
        log.Fatal(err)
    }
    log.Printf("Response: %v", resp)
}
```

### Node.js / TypeScript

**Install:**
```bash
# For private repos, configure npm first:
echo "//gitlab.com/api/v4/projects/:_authToken=${GITLAB_TOKEN}" >> ~/.npmrc

# Install from git with version tag
npm install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/nodejs.git#v1.2.3
```

**package.json example:**
```json
{
  "dependencies": {
    "@gitops-poc-dzha/my-service": "git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/nodejs.git#v1.2.3",
    "@grpc/grpc-js": "^1.10.0",
    "@protobuf-ts/grpc-transport": "^2.9.4"
  }
}
```

**Usage (protobuf-ts):**
```typescript
import { MyServiceClient } from '@gitops-poc-dzha/my-service/myservice/v1/myservice';
import { GrpcTransport } from '@protobuf-ts/grpc-transport';
import { ChannelCredentials } from '@grpc/grpc-js';

async function main() {
    const transport = new GrpcTransport({
        host: 'localhost:9090',
        channelCredentials: ChannelCredentials.createInsecure(),
    });

    const client = new MyServiceClient(transport);

    const { response } = await client.getSomething({ id: '123' });
    console.log('Response:', response);

    transport.close();
}

main();
```

### PHP (Composer)

**Install:**
```bash
# For private repos, configure composer auth:
composer config --global gitlab-token.gitlab.com ${GITLAB_TOKEN}
```

**composer.json example:**
```json
{
  "repositories": [
    {
      "type": "vcs",
      "url": "https://gitlab.com/gitops-poc-dzha/api/gen/my-service/php.git"
    }
  ],
  "require": {
    "php": ">=8.1",
    "grpc/grpc": "^1.57",
    "google/protobuf": "^4.25",
    "gitops-poc-dzha/my-service": "1.2.3"
  }
}
```

Then run:
```bash
composer update
```

**Usage:**
```php
<?php

namespace App;

use GitopsPocDzha\MyService\Myservice\V1\MyServiceClient;
use GitopsPocDzha\MyService\Myservice\V1\GetSomethingRequest;
use Grpc\ChannelCredentials;

class GrpcClient
{
    private MyServiceClient $client;

    public function __construct(string $host = 'localhost:9090')
    {
        $this->client = new MyServiceClient($host, [
            'credentials' => ChannelCredentials::createInsecure(),
        ]);
    }

    public function getSomething(string $id): array
    {
        $request = new GetSomethingRequest();
        $request->setId($id);

        [$response, $status] = $this->client->GetSomething($request)->wait();

        if ($status->code !== \Grpc\STATUS_OK) {
            throw new \RuntimeException("gRPC error: " . $status->details);
        }

        return [
            'id' => $response->getId(),
            'name' => $response->getName(),
        ];
    }
}
```

### Python

**Install:**
```bash
# For private repos, use token in URL:
pip install git+https://oauth2:${GITLAB_TOKEN}@gitlab.com/gitops-poc-dzha/api/gen/my-service/python.git@v1.2.3

# Or for public repos:
pip install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/python.git@v1.2.3
```

**requirements.txt example:**
```
grpcio>=1.62.0
protobuf>=4.25.0
git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/python.git@v1.2.3
```

**Usage:**
```python
import grpc
from myservice.v1 import myservice_pb2, myservice_pb2_grpc

def main():
    channel = grpc.insecure_channel('localhost:9090')
    stub = myservice_pb2_grpc.MyServiceStub(channel)

    request = myservice_pb2.GetSomethingRequest(id='123')

    try:
        response = stub.GetSomething(request)
        print(f"Response: id={response.id}, name={response.name}")
    except grpc.RpcError as e:
        print(f"gRPC error: {e.code()} - {e.details()}")
    finally:
        channel.close()

if __name__ == '__main__':
    main()
```

### Angular (gRPC-Web)

> **Note:** gRPC-Web requires a proxy (Envoy or grpcwebproxy) between browser and gRPC server.

**Install:**
```bash
npm install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/angular.git#v1.2.3
npm install google-protobuf grpc-web
npm install --save-dev @types/google-protobuf
```

**package.json example:**
```json
{
  "dependencies": {
    "@gitops-poc-dzha/my-service-web": "git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/angular.git#main",
    "google-protobuf": "^3.21.0",
    "grpc-web": "^1.5.0"
  },
  "devDependencies": {
    "@types/google-protobuf": "^3.15.12"
  }
}
```

**Dockerfile для Angular с приватными зависимостями:**

Используйте BuildKit secrets для безопасной передачи токена:

```dockerfile
FROM node:22-alpine AS builder
RUN apk add --no-cache git sed
WORKDIR /app
COPY package*.json ./

# BuildKit secret - токен не попадает в слои образа
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        git config --global url."https://gitlab-ci-token:${GITLAB_TOKEN}@gitlab.com/".insteadOf "ssh://git@gitlab.com/" && \
        git config --global url."https://gitlab-ci-token:${GITLAB_TOKEN}@gitlab.com/".insteadOf "https://gitlab.com/" && \
        sed -i 's|git+ssh://git@gitlab.com/|https://gitlab-ci-token:'"${GITLAB_TOKEN}"'@gitlab.com/|g' package-lock.json 2>/dev/null || true; \
    fi && \
    npm ci --prefer-offline --no-audit

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist/my-app /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
CMD ["nginx", "-g", "daemon off;"]
```

**CI/CD (.gitlab-ci.yml):**
```yaml
build:frontend:
  variables:
    DOCKER_BUILDKIT: "1"
  script:
    - echo "$CI_JOB_TOKEN" > /tmp/gitlab_token
    - docker build --secret id=gitlab_token,src=/tmp/gitlab_token -t $IMAGE .
    - rm -f /tmp/gitlab_token
    - docker push $IMAGE
```

**Локальная сборка:**
```bash
# Извлечь токен из ~/.netrc
grep gitlab.com ~/.netrc | sed 's/.*password //' > /tmp/gitlab_token

# Собрать с BuildKit
DOCKER_BUILDKIT=1 docker build --secret id=gitlab_token,src=/tmp/gitlab_token -t my-app .

# Очистить токен
rm -f /tmp/gitlab_token
```

**Usage (Angular Service with Promise Client):**
```typescript
import { Injectable, signal } from '@angular/core';

// Import from installed package
import { MyServicePromiseClient } from '@gitops-poc-dzha/my-service-web/myservice/v1/myservice_grpc_web_pb';
import { GetSomethingRequest, GetSomethingResponse } from '@gitops-poc-dzha/my-service-web/myservice/v1/myservice_pb';

@Injectable({ providedIn: 'root' })
export class MyGrpcService {
  private client: MyServicePromiseClient;
  private _loading = signal(false);
  private _error = signal<string | null>(null);

  loading = this._loading.asReadonly();
  error = this._error.asReadonly();

  constructor() {
    // Hostname should point to API Gateway with gRPC-Web support
    this.client = new MyServicePromiseClient('/api');
  }

  async getSomething(id: string): Promise<GetSomethingResponse | null> {
    this._loading.set(true);
    this._error.set(null);

    try {
      const request = new GetSomethingRequest();
      request.setId(id);

      const response = await this.client.getSomething(request, this.getMetadata());
      return response;
    } catch (err) {
      this._error.set(this.extractError(err));
      return null;
    } finally {
      this._loading.set(false);
    }
  }

  private getMetadata(): { [key: string]: string } {
    const token = localStorage.getItem('access_token');
    return token ? { 'Authorization': `Bearer ${token}` } : {};
  }

  private extractError(err: unknown): string {
    if (err && typeof err === 'object' && 'message' in err) {
      return (err as { message: string }).message;
    }
    return 'Unknown error';
  }
}
```

---

## GitLab Setup

### 1. Create Group Structure

1. Go to GitLab > Groups > New subgroup
2. Create `api` subgroup under `gitops-poc-dzha`
3. Create `proto` and `gen` subgroups under `api`

### 2. Create Personal Access Token

> **IMPORTANT:** You need a **Personal Access Token** (starts with `glpat-`), NOT:
> - ❌ Group Access Token (may not have permissions to create subgroups)
> - ❌ GitLab Agent Token (starts with `glagent-`) - only for Kubernetes
> - ❌ Deploy Token - read-only access

**Steps:**

1. Go to https://gitlab.com/-/user_settings/personal_access_tokens
2. Click **"Add new token"**
3. Configure:
   - **Token name**: `proto-ci`
   - **Expiration date**: set as needed (or leave empty)
   - **Scopes**: ✅ `api` (this is sufficient for all operations)
4. Click **"Create personal access token"**
5. **Copy the token immediately** (starts with `glpat-`, shown only once!)

**Token format verification:**
```
✅ Correct: glpat-xxxxxxxxxxxxxxxxxxxx
❌ Wrong:   glagent-xxxxxxxxxxxxxxxxxx  (Agent Token)
❌ Wrong:   glptt-xxxxxxxxxxxxxxxxxx    (Project Token)
```

### 3. Get Gen Group ID

```bash
curl --header "PRIVATE-TOKEN: glpat-xxx" \
  "https://gitlab.com/api/v4/groups/gitops-poc-dzha%2Fapi%2Fgen" | jq .id
```

### 4. Configure CI/CD Variables

Go to `gitops-poc-dzha/api` group > Settings > CI/CD > Variables

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `CI_PUSH_TOKEN` | `glpat-xxx...` (Personal Access Token) | **No** | Yes |
| `GEN_GROUP_ID` | `12345678` (ID from step 3) | No | No |

> **CRITICAL Settings for CI_PUSH_TOKEN:**
> - **Protected**: ❌ **NO** - must be unchecked so it works on tags
> - **Masked**: ✅ Yes - hides token in logs
> - **Value**: Must start with `glpat-`

### 5. Verify No Conflicting Variables

CI/CD variables are inherited from parent groups. Check that `CI_PUSH_TOKEN` is not set at other levels with wrong value:

- `gitops-poc-dzha` group level
- `gitops-poc-dzha/api` group level
- `gitops-poc-dzha/api/proto` group level
- Individual project level

If the same variable exists at multiple levels, the most specific (project level) takes precedence.

---

## Proto File Best Practices

### Package Naming

```protobuf
syntax = "proto3";

// Package follows: {domain}.{subdomain}.v{major}
package myservice.v1;

// Language-specific options
option go_package = "gitlab.com/gitops-poc-dzha/api/gen/my-service/go/myservice/v1;myservicev1";
option php_namespace = "GitopsPocDzha\\MyService\\Myservice\\V1";
option java_package = "com.gitopspocdzha.myservice.myservice.v1";
```

### Versioning Guidelines

- Use `v1`, `v2`, etc. directories for major API versions
- Minor and patch versions are tracked via git tags only
- Never reuse field numbers (use `reserved` for removed fields)

### Breaking Changes

The CI pipeline detects breaking changes including:
- Removing/renaming services or methods
- Changing field numbers or types
- Removing required fields

If breaking changes are needed:
1. Create a new API version (`v2`)
2. Keep old version available for migration period

---

## gRPC-Web Proxy Configuration

Angular/browser clients need a gRPC-Web proxy. Options:

### Option A: Add to Existing Envoy (Recommended)

Add to your Envoy configuration:
```yaml
http_filters:
  - name: envoy.filters.http.grpc_web
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
  - name: envoy.filters.http.cors
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
  - name: envoy.filters.http.router
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

### Option B: Standalone grpcwebproxy

```bash
docker run -d --name grpcwebproxy \
  -p 8080:8080 \
  mwitkow/grpc-web-proxy \
  --backend_addr=grpc-backend:9090 \
  --run_tls_server=false \
  --allow_all_origins
```

---

## CI/CD Pipeline Overview

The pipeline is defined in the `proto-gen` CI/CD Component at [api/ci](https://gitlab.com/gitops-poc-dzha/api/ci).

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ proto-lint  │────▶│proto-breaking────▶│proto-generate───▶│proto-publish│
│             │     │             │     │             │     │             │
│ buf lint    │     │ buf breaking│     │ buf generate│     │ Create      │
│             │     │ --against   │     │             │     │ sub-group + │
│             │     │ main        │     │             │     │ lang repos  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

### Stages

1. **proto-lint** - Validates proto file quality and style
2. **proto-breaking** - Detects breaking changes against main branch
3. **proto-generate** - Generates code for selected languages using Buf
4. **proto-publish** - Creates sub-group, repositories, and pushes generated code

### Triggers

- **dev branch**: Generates v0.0.0-{sha} snapshot
- **main branch**: Generates v0.0.0-{sha} snapshot
- **Git tag (vX.Y.Z)**: Generates versioned release with tag in each language repo
- **Merge Request** (optional): Runs lint and breaking checks only

---

## Troubleshooting

### Pipeline fails at lint stage

Check your proto files for:
- Missing package declaration
- Invalid field numbers

Run locally:
```bash
buf lint
```

### Pipeline fails at breaking stage

You introduced a breaking change. Options:
1. Revert the breaking change
2. Create a new API version (v2)

### Sub-group or repositories not created

Check:
1. `CI_PUSH_TOKEN` has `api` scope and Owner role
2. `GEN_GROUP_ID` is correct
3. Token is **not protected** (so it works on tags)

### Go module not found

Для приватных репозиториев настройте аутентификацию через `.netrc`:

```bash
# 1. Установите переменные окружения
export GOPRIVATE=gitlab.com/gitops-poc-dzha/*
export GONOSUMDB=gitlab.com/gitops-poc-dzha/*
export GONOPROXY=gitlab.com/gitops-poc-dzha/*

# 2. Создайте ~/.netrc с токеном (scope: read_api)
echo "machine gitlab.com login YOUR_USERNAME password YOUR_TOKEN" > ~/.netrc
chmod 600 ~/.netrc

# 3. Проверьте что работает
go mod download
```

> **НЕ используйте** `git config insteadOf` - это не работает с вложенными GitLab subgroups.
> Используйте `.netrc` с токеном, имеющим scope `read_api`.

### Package installation fails

For private repositories, configure authentication:

**Go:**
```bash
# Используйте .netrc (НЕ git config insteadOf!)
export GOPRIVATE=gitlab.com/gitops-poc-dzha/*
export GONOSUMDB=gitlab.com/gitops-poc-dzha/*
export GONOPROXY=gitlab.com/gitops-poc-dzha/*
echo "machine gitlab.com login YOUR_USERNAME password YOUR_TOKEN" > ~/.netrc
chmod 600 ~/.netrc
```

**npm:**
```bash
npm config set //gitlab.com/api/v4/packages/npm/:_authToken ${GITLAB_TOKEN}
```

**Composer:**
```bash
composer config --global gitlab-token.gitlab.com ${GITLAB_TOKEN}
```

**pip:**
```bash
pip install git+https://oauth2:${GITLAB_TOKEN}@gitlab.com/...
```
