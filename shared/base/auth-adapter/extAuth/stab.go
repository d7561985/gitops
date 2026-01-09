package extAuth

import (
	"context"
	"errors"
	"os"

	"google.golang.org/grpc"
)

// NewAuthSessionServiceClient creates an AuthSessionServiceClient
// If USE_USER_SERVICE=true, uses real gRPC client to user-service
// Otherwise, uses stub with hardcoded demo tokens
func NewAuthSessionServiceClient(conn *grpc.ClientConn) AuthSessionServiceClient {
	if os.Getenv("USE_USER_SERVICE") == "true" {
		return NewGRPCAuthSessionServiceClient(conn)
	}
	return &stab{}
}

type stab struct {
}

// ValidateSession - demo stub that validates tokens
// Valid tokens: "demo-token", "test-token", "valid-session"
// Returns user-id and session-id headers on success
func (s stab) ValidateSession(ctx context.Context, req *ValidateSessionRequest, opt ...grpc.CallOption) (*ValidateSessionResponse, error) {
	// Check if token is provided
	if req.SessionToken == "" {
		return nil, errors.New("no token provided")
	}

	// Demo: accept specific test tokens
	validTokens := map[string]bool{
		"demo-token":    true,
		"test-token":    true,
		"valid-session": true,
	}

	if !validTokens[req.SessionToken] {
		return nil, errors.New("invalid token")
	}

	// Return successful response with demo user data
	return &ValidateSessionResponse{
		UserId:    "demo-user-123",
		SessionId: "session-456",
		Roles: []*Role{
			{
				Name: "CLIENT",
				Permissions: []*Permission{
					{Name: "read"},
					{Name: "write"},
				},
			},
		},
	}, nil
}
