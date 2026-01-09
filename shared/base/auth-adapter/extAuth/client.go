package extAuth

import (
	"context"

	"google.golang.org/grpc"
	userv1 "gitlab.com/gitops-poc-dzha/api/gen/user-service/go/user/v1"
)

// grpcClient implements AuthSessionServiceClient using the generated proto code
type grpcClient struct {
	client userv1.AuthSessionServiceClient
}

// NewGRPCAuthSessionServiceClient creates a new gRPC client for user-service
// Use this instead of NewAuthSessionServiceClient when user-service is available
func NewGRPCAuthSessionServiceClient(conn *grpc.ClientConn) AuthSessionServiceClient {
	return &grpcClient{
		client: userv1.NewAuthSessionServiceClient(conn),
	}
}

// ValidateSession validates a JWT token by calling user-service
func (c *grpcClient) ValidateSession(ctx context.Context, req *ValidateSessionRequest, opts ...grpc.CallOption) (*ValidateSessionResponse, error) {
	// Call user-service via gRPC
	resp, err := c.client.ValidateSession(ctx, &userv1.ValidateSessionRequest{
		SessionToken: req.SessionToken,
	}, opts...)
	if err != nil {
		return nil, err
	}

	// Map proto response to internal types
	roles := make([]*Role, 0, len(resp.Roles))
	for _, r := range resp.Roles {
		perms := make([]*Permission, 0, len(r.Permissions))
		for _, p := range r.Permissions {
			perms = append(perms, &Permission{Name: p.Name})
		}
		roles = append(roles, &Role{Name: r.Name, Permissions: perms})
	}

	return &ValidateSessionResponse{
		UserId:    resp.UserId,
		SessionId: resp.SessionId,
		Roles:     roles,
	}, nil
}
