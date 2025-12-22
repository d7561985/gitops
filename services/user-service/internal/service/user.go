package service

import (
	"context"
	"errors"

	"gitlab.com/gitops-poc-dzha/user-service/internal/config"
	"gitlab.com/gitops-poc-dzha/user-service/internal/domain"
	"gitlab.com/gitops-poc-dzha/user-service/internal/events"
	"gitlab.com/gitops-poc-dzha/user-service/internal/jwt"
	"gitlab.com/gitops-poc-dzha/user-service/internal/repository/mongodb"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserNotFound       = errors.New("user not found")
)

// UserService handles user operations
type UserService struct {
	userRepo         *mongodb.UserRepository
	refreshTokenRepo *mongodb.RefreshTokenRepository
	jwtManager       *jwt.Manager
	eventPublisher   *events.Publisher
	cfg              *config.Config
}

// NewUserService creates a new user service
func NewUserService(
	userRepo *mongodb.UserRepository,
	refreshTokenRepo *mongodb.RefreshTokenRepository,
	jwtManager *jwt.Manager,
	eventPublisher *events.Publisher,
	cfg *config.Config,
) *UserService {
	return &UserService{
		userRepo:         userRepo,
		refreshTokenRepo: refreshTokenRepo,
		jwtManager:       jwtManager,
		eventPublisher:   eventPublisher,
		cfg:              cfg,
	}
}

// TokenPair represents access and refresh tokens
type TokenPair struct {
	AccessToken  string
	RefreshToken string
}

// Register creates a new user account
func (s *UserService) Register(ctx context.Context, email, password, username string) (string, *TokenPair, error) {
	// Hash password
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", nil, err
	}

	// Create user
	user := &domain.User{
		Email:        email,
		PasswordHash: string(passwordHash),
		Username:     username,
		Roles:        []string{domain.RoleClient},
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return "", nil, err
	}

	// Generate tokens
	tokens, err := s.generateTokens(ctx, user)
	if err != nil {
		return "", nil, err
	}

	// Publish event
	if s.eventPublisher != nil {
		_ = s.eventPublisher.PublishUserRegistered(ctx, user.ID.Hex(), email)
	}

	return user.ID.Hex(), tokens, nil
}

// Login authenticates a user
func (s *UserService) Login(ctx context.Context, email, password string) (string, *TokenPair, error) {
	// Find user
	user, err := s.userRepo.FindByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, mongodb.ErrUserNotFound) {
			return "", nil, ErrInvalidCredentials
		}
		return "", nil, err
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return "", nil, ErrInvalidCredentials
	}

	// Generate tokens
	tokens, err := s.generateTokens(ctx, user)
	if err != nil {
		return "", nil, err
	}

	// Publish event (session_id is in the JWT)
	if s.eventPublisher != nil {
		claims, _ := s.jwtManager.ValidateToken(tokens.AccessToken)
		if claims != nil {
			_ = s.eventPublisher.PublishUserLogin(ctx, user.ID.Hex(), claims.SessionID)
		}
	}

	return user.ID.Hex(), tokens, nil
}

// Logout invalidates the current session
func (s *UserService) Logout(ctx context.Context, userID, sessionID string) error {
	// Delete refresh token for this session
	if err := s.refreshTokenRepo.DeleteBySessionID(ctx, sessionID); err != nil {
		return err
	}

	// Publish event
	if s.eventPublisher != nil {
		_ = s.eventPublisher.PublishUserLogout(ctx, userID, sessionID)
	}

	return nil
}

// RefreshToken exchanges a refresh token for new tokens
func (s *UserService) RefreshToken(ctx context.Context, refreshToken string) (*TokenPair, error) {
	// Find and validate refresh token
	token, err := s.refreshTokenRepo.Find(ctx, refreshToken)
	if err != nil {
		return nil, err
	}

	// Delete old refresh token (rotation)
	if err := s.refreshTokenRepo.Delete(ctx, refreshToken); err != nil {
		return nil, err
	}

	// Find user
	user, err := s.userRepo.FindByID(ctx, token.UserID)
	if err != nil {
		return nil, err
	}

	// Generate new tokens with same session ID
	sessionID := token.SessionID
	accessToken, err := s.jwtManager.GenerateAccessToken(user.ID.Hex(), sessionID, user.Roles)
	if err != nil {
		return nil, err
	}

	newRefreshToken, err := jwt.GenerateRefreshToken(s.cfg.RefreshTokenLength)
	if err != nil {
		return nil, err
	}

	if err := s.refreshTokenRepo.Create(ctx, newRefreshToken, user.ID, sessionID, s.cfg.RefreshTokenTTL); err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
	}, nil
}

// GetProfile returns user profile
func (s *UserService) GetProfile(ctx context.Context, userID string) (*domain.User, error) {
	id, err := primitive.ObjectIDFromHex(userID)
	if err != nil {
		return nil, ErrUserNotFound
	}

	return s.userRepo.FindByID(ctx, id)
}

// generateTokens creates a new access and refresh token pair
func (s *UserService) generateTokens(ctx context.Context, user *domain.User) (*TokenPair, error) {
	sessionID, err := jwt.GenerateSessionID()
	if err != nil {
		return nil, err
	}

	accessToken, err := s.jwtManager.GenerateAccessToken(user.ID.Hex(), sessionID, user.Roles)
	if err != nil {
		return nil, err
	}

	refreshToken, err := jwt.GenerateRefreshToken(s.cfg.RefreshTokenLength)
	if err != nil {
		return nil, err
	}

	if err := s.refreshTokenRepo.Create(ctx, refreshToken, user.ID, sessionID, s.cfg.RefreshTokenTTL); err != nil {
		return nil, err
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
	}, nil
}
