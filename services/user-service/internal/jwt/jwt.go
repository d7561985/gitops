package jwt

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrExpiredToken = errors.New("token expired")
)

// Claims represents JWT claims
type Claims struct {
	UserID    string   `json:"user_id"`
	SessionID string   `json:"session_id"`
	Roles     []string `json:"roles"`
	jwt.RegisteredClaims
}

// Manager handles JWT operations
type Manager struct {
	secret         []byte
	accessTokenTTL time.Duration
}

// NewManager creates a new JWT manager
func NewManager(secret string, accessTokenTTL time.Duration) *Manager {
	return &Manager{
		secret:         []byte(secret),
		accessTokenTTL: accessTokenTTL,
	}
}

// GenerateAccessToken creates a new JWT access token
func (m *Manager) GenerateAccessToken(userID, sessionID string, roles []string) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID:    userID,
		SessionID: sessionID,
		Roles:     roles,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(m.accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    "user-service",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.secret)
}

// ValidateToken validates a JWT token and returns claims
func (m *Manager) ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return m.secret, nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrExpiredToken
		}
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

// GenerateRefreshToken creates a random refresh token
func GenerateRefreshToken(length int) (string, error) {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// GenerateSessionID creates a unique session ID
func GenerateSessionID() (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}
