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

## Quick Start: Creating a New Proto Service

### Step 1: Copy the Template

```bash
# From gitops repository root
cp -r templates/proto-service my-service
cd my-service
```

### Step 2: Update Configuration

Edit `buf.yaml`:
```yaml
modules:
  - path: proto
    name: buf.build/gitops-poc-dzha/my-service  # Change to your service name
```

Edit `buf.gen.yaml`:
```yaml
managed:
  override:
    - file_option: go_package_prefix
      value: gitlab.com/gitops-poc-dzha/api/gen/my-service/go  # Change to your service
```

### Step 3: Configure CI/CD

The `.gitlab-ci.yml` uses CI/CD Components - just include the proto-gen component:

```yaml
include:
  - component: gitlab.com/gitops-poc-dzha/api/ci/proto-gen@1.0.0
    inputs:
      languages: [go, nodejs, php, python, angular]
```

**Available inputs:**

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `languages` | array | `[go, nodejs, php, python, angular]` | Languages to generate |
| `buf_version` | string | `1.47.2` | Buf CLI version |
| `gen_group_path` | string | `gitops-poc-dzha/api/gen` | GitLab group for generated repos |
| `run_on_mr` | boolean | `true` | Run lint/breaking on MRs |

**Example - generate only Go and Node.js:**
```yaml
include:
  - component: gitlab.com/gitops-poc-dzha/api/ci/proto-gen@1.0.0
    inputs:
      languages: [go, nodejs]
```

### Step 4: Write Your Proto Files

Create proto files in `proto/{domain}/v1/`:
```bash
mkdir -p proto/myservice/v1
```

Example structure:
```
proto/
└── myservice/
    └── v1/
        ├── myservice.proto    # Service definitions
        └── types.proto        # Shared message types
```

### Step 5: Push to GitLab

```bash
git init
git add .
git commit -m "Initial proto definitions"
git remote add origin https://gitlab.com/gitops-poc-dzha/api/proto/my-service.git
git push -u origin main
```

### Step 6: CI Does the Rest

The pipeline automatically:
1. Lints your proto files
2. Checks for breaking changes
3. Generates code for selected languages
4. Creates `api/gen/my-service/` sub-group if it doesn't exist
5. Creates language repositories (go, nodejs, php, python, angular)
6. Pushes generated code with proper versioning
7. Creates git tags for releases

---

## Using Generated Packages

### Go

**Install:**
```bash
# For private GitLab repos, configure git first:
git config --global url."git@gitlab.com:".insteadOf "https://gitlab.com/"

# Or with token:
git config --global url."https://oauth2:${GITLAB_TOKEN}@gitlab.com".insteadOf "https://gitlab.com"

# Install specific version
go get gitlab.com/gitops-poc-dzha/api/gen/my-service/go@v1.2.3

# Install dev snapshot
go get gitlab.com/gitops-poc-dzha/api/gen/my-service/go@v0.0.0-abc1234
```

**go.mod example:**
```go
module my-app

go 1.21

require (
    gitlab.com/gitops-poc-dzha/api/gen/my-service/go v1.2.3
)
```

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
```

**package.json example:**
```json
{
  "dependencies": {
    "@gitops-poc-dzha/my-service-web": "git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service/angular.git#v1.2.3",
    "google-protobuf": "^3.21.0",
    "grpc-web": "^1.5.0"
  }
}
```

**Usage (Angular Service):**
```typescript
import { Injectable } from '@angular/core';
import { Observable, from } from 'rxjs';

import { MyServiceClient } from '@gitops-poc-dzha/my-service-web/myservice/v1/MyserviceServiceClientPb';
import { GetSomethingRequest, GetSomethingResponse } from '@gitops-poc-dzha/my-service-web/myservice/v1/myservice_pb';

@Injectable({ providedIn: 'root' })
export class MyGrpcService {
  private client: MyServiceClient;

  constructor() {
    this.client = new MyServiceClient('https://grpc.example.com');
  }

  getSomething(id: string): Observable<GetSomethingResponse> {
    const request = new GetSomethingRequest();
    request.setId(id);

    return from(
      new Promise<GetSomethingResponse>((resolve, reject) => {
        this.client.getSomething(request, {}, (err, response) => {
          if (err) {
            reject(new Error(`gRPC error: ${err.message}`));
          } else if (response) {
            resolve(response);
          }
        });
      })
    );
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

Ensure git is configured for private repos:
```bash
git config --global url."git@gitlab.com:".insteadOf "https://gitlab.com/"
```

### Package installation fails

For private repositories, configure authentication:

**Go:**
```bash
git config --global url."git@gitlab.com:".insteadOf "https://gitlab.com/"
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
