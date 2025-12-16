# Proto Service Template

This is a template for creating a new proto/gRPC service definition repository.

## Quick Start

### 1. Copy this template

```bash
cp -r templates/proto-service api/proto/my-service
cd api/proto/my-service
```

### 2. Update configuration files

**buf.yaml** - Change the module name:
```yaml
name: buf.build/gitops-poc-dzha/my-service  # <-- Change this
```

**buf.gen.yaml** - Change the Go package prefix:
```yaml
managed:
  override:
    - file_option: go_package_prefix
      value: gitlab.com/gitops-poc-dzha/api/gen/my-service/go  # <-- Change this
```

### 3. Create your proto files

Replace the example proto files in `proto/example/v1/` with your own:

```bash
rm -rf proto/example
mkdir -p proto/myservice/v1
```

Create your proto file following the patterns in `proto/example/v1/example.proto`.

### 4. Validate locally (optional)

```bash
# Install buf: https://buf.build/docs/installation
buf lint
buf format --diff
```

### 5. Push to GitLab

```bash
rm -rf .git  # Remove template git history
git init
git add .
git commit -m "Initial proto definitions for my-service"
git remote add origin https://gitlab.com/gitops-poc-dzha/api/proto/my-service.git
git push -u origin main
```

## What Happens Next

The CI pipeline will automatically:

1. **Lint** - Validate proto file quality
2. **Breaking** - Check for breaking changes
3. **Generate** - Create code for Go, Node.js, PHP, Python, Angular
4. **Publish** - Push to `api/gen/my-service` repository

## Directory Structure

```
my-service/
├── buf.yaml           # Buf module configuration
├── buf.gen.yaml       # Code generation configuration
├── .gitlab-ci.yml     # CI/CD pipeline
├── README.md          # This file
└── proto/
    └── myservice/     # Your service domain
        └── v1/        # API version
            ├── myservice.proto    # Service definitions
            └── types.proto        # Shared types (optional)
```

## Versioning

| Branch | Version Format | Example |
|--------|----------------|---------|
| dev | v0.0.0-{sha} | v0.0.0-abc1234 |
| main | v0.0.0-{sha} | v0.0.0-def5678 |
| tag | v{X}.{Y}.{Z} | v1.2.3 |

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

option go_package = "gitlab.com/gitops-poc-dzha/api/gen/my-service/go/myservice/v1;myservicev1";
option php_namespace = "GitopsPocDzha\\MyService\\Myservice\\V1";
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

### Field Numbering

- Use sequential field numbers
- Reserve deleted fields to prevent reuse
- Never reuse field numbers

```protobuf
message User {
  string id = 1;
  string email = 2;
  // Field 3 was removed
  reserved 3;
  string name = 4;
}
```

## Using Generated Code

After the pipeline runs, code will be available at:
`gitlab.com/gitops-poc-dzha/api/gen/my-service`

### Go
```bash
go get gitlab.com/gitops-poc-dzha/api/gen/my-service/go@v1.0.0
```

### Node.js
```bash
npm install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service.git#v1.0.0
```

### PHP
```json
{
  "repositories": [{"type": "vcs", "url": "https://gitlab.com/gitops-poc-dzha/api/gen/my-service.git"}],
  "require": {"gitops-poc-dzha/my-service": "1.0.0"}
}
```

### Python
```bash
pip install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service.git@v1.0.0#subdirectory=python
```

### Angular (gRPC-Web)
```bash
npm install git+https://gitlab.com/gitops-poc-dzha/api/gen/my-service.git#v1.0.0
```

## Documentation

For detailed documentation, see:
[Proto/gRPC Infrastructure Guide](../../docs/proto-grpc-infrastructure.md)
