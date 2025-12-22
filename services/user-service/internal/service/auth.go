package service

import (
	"context"

	"gitlab.com/gitops-poc-dzha/user-service/internal/domain"
	"gitlab.com/gitops-poc-dzha/user-service/internal/jwt"
)

// AuthService handles authentication operations for auth-adapter
type AuthService struct {
	jwtManager *jwt.Manager
}

// NewAuthService creates a new auth service
func NewAuthService(jwtManager *jwt.Manager) *AuthService {
	return &AuthService{
		jwtManager: jwtManager,
	}
}

// SessionInfo contains validated session information
type SessionInfo struct {
	UserID    string
	SessionID string
	Roles     []RoleInfo
}

// RoleInfo contains role and permissions
type RoleInfo struct {
	Name        string
	Permissions []string
}

// ValidateSession validates a JWT token and returns session info
func (s *AuthService) ValidateSession(ctx context.Context, token string) (*SessionInfo, error) {
	claims, err := s.jwtManager.ValidateToken(token)
	if err != nil {
		return nil, err
	}

	// Build role info with permissions
	roles := make([]RoleInfo, 0, len(claims.Roles))
	for _, roleName := range claims.Roles {
		roles = append(roles, RoleInfo{
			Name:        roleName,
			Permissions: domain.DefaultPermissions(roleName),
		})
	}

	return &SessionInfo{
		UserID:    claims.UserID,
		SessionID: claims.SessionID,
		Roles:     roles,
	}, nil
}
