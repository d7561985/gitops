package main

import (
	"context"
	"errors"
	"fmt"
	"log"

	"connectrpc.com/connect"
	"gitlab.com/gitops-poc-dzha/user-service/internal/domain"
	"gitlab.com/gitops-poc-dzha/user-service/internal/repository/mongodb"
	"gitlab.com/gitops-poc-dzha/user-service/internal/service"

	userv1 "gitlab.com/gitops-poc-dzha/api/gen/user-service/go/user/v1"
)

// ============================================================================
// UserServiceServer - implements userv1connect.UserServiceHandler
// ============================================================================

type UserServiceServer struct {
	svc *service.UserService
}

func NewUserServiceServer(svc *service.UserService) *UserServiceServer {
	return &UserServiceServer{svc: svc}
}

func (s *UserServiceServer) Register(ctx context.Context, req *connect.Request[userv1.RegisterRequest]) (*connect.Response[userv1.RegisterResponse], error) {
	log.Printf("[DEBUG] Register called: email=%s, username=%s", req.Msg.Email, req.Msg.Username)

	// Log incoming headers
	log.Printf("[DEBUG] Register headers: %v", req.Header())

	if req.Msg.Email == "" || req.Msg.Password == "" || req.Msg.Username == "" {
		log.Printf("[DEBUG] Register validation failed: missing required fields")
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("email, password and username are required"))
	}

	userID, tokens, err := s.svc.Register(ctx, req.Msg.Email, req.Msg.Password, req.Msg.Username)
	if err != nil {
		if errors.Is(err, mongodb.ErrUserAlreadyExists) {
			log.Printf("[DEBUG] Register failed: user already exists (email=%s)", req.Msg.Email)
			return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("user with this email already exists"))
		}
		log.Printf("[DEBUG] Register failed: %v", err)
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to register: %w", err))
	}

	log.Printf("[DEBUG] Register success: userID=%s", userID)
	return connect.NewResponse(&userv1.RegisterResponse{
		UserId:       userID,
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
	}), nil
}

func (s *UserServiceServer) Login(ctx context.Context, req *connect.Request[userv1.LoginRequest]) (*connect.Response[userv1.LoginResponse], error) {
	log.Printf("[DEBUG] Login called: email=%s", req.Msg.Email)

	// Log incoming headers
	log.Printf("[DEBUG] Login headers: %v", req.Header())

	if req.Msg.Email == "" || req.Msg.Password == "" {
		log.Printf("[DEBUG] Login validation failed: missing required fields")
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("email and password are required"))
	}

	userID, tokens, err := s.svc.Login(ctx, req.Msg.Email, req.Msg.Password)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCredentials) {
			log.Printf("[DEBUG] Login failed: invalid credentials (email=%s)", req.Msg.Email)
			return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid email or password"))
		}
		log.Printf("[DEBUG] Login failed: %v", err)
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to login: %w", err))
	}

	log.Printf("[DEBUG] Login success: userID=%s", userID)
	return connect.NewResponse(&userv1.LoginResponse{
		UserId:       userID,
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
	}), nil
}

func (s *UserServiceServer) Logout(ctx context.Context, req *connect.Request[userv1.LogoutRequest]) (*connect.Response[userv1.LogoutResponse], error) {
	userID, err := getUserIDFromRequest(req)
	if err != nil {
		return nil, err
	}

	sessionID, err := getSessionIDFromRequest(req)
	if err != nil {
		return nil, err
	}

	if err := s.svc.Logout(ctx, userID, sessionID); err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to logout: %w", err))
	}

	return connect.NewResponse(&userv1.LogoutResponse{}), nil
}

func (s *UserServiceServer) RefreshToken(ctx context.Context, req *connect.Request[userv1.RefreshTokenRequest]) (*connect.Response[userv1.RefreshTokenResponse], error) {
	if req.Msg.RefreshToken == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("refresh_token is required"))
	}

	tokens, err := s.svc.RefreshToken(ctx, req.Msg.RefreshToken)
	if err != nil {
		if errors.Is(err, mongodb.ErrRefreshTokenNotFound) || errors.Is(err, mongodb.ErrRefreshTokenExpired) {
			return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid or expired refresh token"))
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to refresh token: %w", err))
	}

	return connect.NewResponse(&userv1.RefreshTokenResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
	}), nil
}

func (s *UserServiceServer) GetProfile(ctx context.Context, req *connect.Request[userv1.GetProfileRequest]) (*connect.Response[userv1.GetProfileResponse], error) {
	userID, err := getUserIDFromRequest(req)
	if err != nil {
		return nil, err
	}

	user, err := s.svc.GetProfile(ctx, userID)
	if err != nil {
		if errors.Is(err, mongodb.ErrUserNotFound) {
			return nil, connect.NewError(connect.CodeNotFound, errors.New("user not found"))
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to get profile: %w", err))
	}

	return connect.NewResponse(&userv1.GetProfileResponse{
		UserId:   user.ID.Hex(),
		Email:    user.Email,
		Username: user.Username,
		Roles:    user.Roles,
	}), nil
}

// ============================================================================
// AuthSessionServiceServer - implements userv1connect.AuthSessionServiceHandler
// ============================================================================

type AuthSessionServiceServer struct {
	svc *service.AuthService
}

func NewAuthSessionServiceServer(svc *service.AuthService) *AuthSessionServiceServer {
	return &AuthSessionServiceServer{svc: svc}
}

func (s *AuthSessionServiceServer) ValidateSession(ctx context.Context, req *connect.Request[userv1.ValidateSessionRequest]) (*connect.Response[userv1.ValidateSessionResponse], error) {
	log.Printf("[DEBUG] ValidateSession called")

	if req.Msg.SessionToken == "" {
		log.Printf("[DEBUG] ValidateSession failed: empty token")
		return nil, connect.NewError(connect.CodeInvalidArgument, errors.New("session_token is required"))
	}

	info, err := s.svc.ValidateSession(ctx, req.Msg.SessionToken)
	if err != nil {
		log.Printf("[DEBUG] ValidateSession failed: %v", err)
		return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid or expired token"))
	}
	log.Printf("[DEBUG] ValidateSession success: userID=%s, sessionID=%s", info.UserID, info.SessionID)

	// Convert roles to proto format
	roles := make([]*userv1.Role, 0, len(info.Roles))
	for _, r := range info.Roles {
		perms := make([]*userv1.Permission, 0, len(r.Permissions))
		for _, p := range r.Permissions {
			perms = append(perms, &userv1.Permission{Name: p})
		}
		roles = append(roles, &userv1.Role{
			Name:        r.Name,
			Permissions: perms,
		})
	}

	return connect.NewResponse(&userv1.ValidateSessionResponse{
		UserId:    info.UserID,
		SessionId: info.SessionID,
		Roles:     roles,
	}), nil
}

// ============================================================================
// Helpers
// ============================================================================

// getUserIDFromRequest extracts user-id from request headers (set by auth-adapter)
func getUserIDFromRequest[T any](req *connect.Request[T]) (string, error) {
	userID := req.Header().Get("user-id")
	if userID == "" {
		return "", connect.NewError(connect.CodeUnauthenticated, errors.New("missing user-id header"))
	}
	return userID, nil
}

// getSessionIDFromRequest extracts session-id from request headers
func getSessionIDFromRequest[T any](req *connect.Request[T]) (string, error) {
	sessionID := req.Header().Get("session-id")
	if sessionID == "" {
		return "", connect.NewError(connect.CodeUnauthenticated, errors.New("missing session-id header"))
	}
	return sessionID, nil
}

// Ensure domain package is used
var _ = domain.RoleClient

// ============================================================================
// Interceptors
// ============================================================================

// NewLoggingInterceptor creates an interceptor for request/response logging
func NewLoggingInterceptor() connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			procedure := req.Spec().Procedure
			log.Printf("[RPC] %s started", procedure)

			resp, err := next(ctx, req)

			if err != nil {
				log.Printf("[RPC] %s failed: %v", procedure, err)
			} else {
				log.Printf("[RPC] %s completed", procedure)
			}

			return resp, err
		}
	}
}
