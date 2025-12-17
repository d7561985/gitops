# Proto Service Template (Zero-Config)

Create a new proto/gRPC service with just 2 files!

## Quick Start

### 1. Create your service directory

```bash
mkdir -p my-service/proto/myservice/v1
cd my-service
```

### 2. Add CI configuration

```bash
cp /path/to/templates/proto-service/.gitlab-ci.yml .
# Or just create it manually (it's only 3 lines!)
```

### 3. Create your proto file

```bash
cat > proto/myservice/v1/service.proto << 'EOF'
syntax = "proto3";

package myservice.v1;

service MyService {
  rpc GetItem(GetItemRequest) returns (GetItemResponse);
  rpc CreateItem(CreateItemRequest) returns (CreateItemResponse);
}

message GetItemRequest {
  string id = 1;
}

message GetItemResponse {
  string id = 1;
  string name = 2;
}

message CreateItemRequest {
  string name = 1;
}

message CreateItemResponse {
  string id = 1;
}
EOF
```

### 4. Push to GitLab

```bash
git init
git add .
git commit -m "Initial proto definitions"
git remote add origin https://gitlab.com/gitops-poc-dzha/api/proto/my-service.git
git push -u origin main
```

**That's it!** No `buf.yaml` or `buf.gen.yaml` needed.

## What Happens Automatically

The CI pipeline will:

1. **Generate** `buf.yaml` from `$CI_PROJECT_NAME`
2. **Generate** `buf.gen.yaml` with all language plugins
3. **Lint** - Validate proto file quality
4. **Breaking** - Check for breaking changes (on MR/dev)
5. **Generate** - Create code for Go, Node.js, PHP, Python, Angular
6. **Publish** - Push to `api/gen/{service}/{language}/`

## Directory Structure

```
my-service/
├── .gitlab-ci.yml     # CI/CD pipeline (copy from template)
└── proto/
    └── myservice/     # Your service domain
        └── v1/        # API version
            └── service.proto
```

## Versioning

| Trigger | Version Format | Example |
|---------|----------------|---------|
| Push to dev | `v0.0.0-{sha}` | `v0.0.0-abc1234` |
| Push to main | `v0.0.0-{sha}` | `v0.0.0-def5678` |
| Git tag | `v{X}.{Y}.{Z}` | `v1.2.3` |

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Proto File Guidelines

### Package Naming

```protobuf
syntax = "proto3";
package myservice.v1;
// go_package is auto-managed by buf, no need to specify!
```

### Service Naming

- Services should end with `Service` suffix
- Methods should be descriptive verbs

```protobuf
service UserService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc CreateUser(CreateUserRequest) returns (CreateUserResponse);
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
}
```

## Using Generated Code

After the pipeline runs, code will be available at:
`gitlab.com/gitops-poc-dzha/api/gen/{service}/{language}`

### Go
```bash
go get gitlab.com/gitops-poc-dzha/api/gen/my-service/go@v1.0.0
```

### Node.js
```bash
npm install @gitops-poc-dzha/my-service@1.0.0
```

### Python
```bash
pip install gitops-poc-dzha-my-service==1.0.0
```

### PHP
```bash
composer require gitops-poc-dzha/my-service:1.0.0
```

## Customization (Optional)

Override defaults in your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'gitops-poc-dzha/api/ci'
    file: '/templates/proto-gen/template.yml'

variables:
  PROTO_GEN_LANGUAGES: "go,nodejs"  # Only these languages
  BUF_VERSION: "1.48.0"             # Specific Buf version
```

## Documentation

For detailed documentation, see:
[Proto/gRPC Infrastructure Guide](../../docs/proto-grpc-infrastructure.md)
