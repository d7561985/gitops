package domain

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// User represents a user in the system
type User struct {
	ID           primitive.ObjectID `bson:"_id,omitempty"`
	Email        string             `bson:"email"`
	PasswordHash string             `bson:"password_hash"`
	Username     string             `bson:"username"`
	Roles        []string           `bson:"roles"`
	CreatedAt    time.Time          `bson:"created_at"`
	UpdatedAt    time.Time          `bson:"updated_at"`
}

// RefreshToken represents a refresh token stored in MongoDB
type RefreshToken struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	TokenHash string             `bson:"token_hash"`
	UserID    primitive.ObjectID `bson:"user_id"`
	SessionID string             `bson:"session_id"`
	ExpiresAt time.Time          `bson:"expires_at"`
	CreatedAt time.Time          `bson:"created_at"`
}

// Role constants
const (
	RoleClient = "CLIENT"
	RoleAdmin  = "ADMIN"
)

// Permission constants
const (
	PermissionRead  = "read"
	PermissionWrite = "write"
	PermissionAdmin = "admin"
)

// DefaultPermissions returns default permissions for a role
func DefaultPermissions(role string) []string {
	switch role {
	case RoleAdmin:
		return []string{PermissionRead, PermissionWrite, PermissionAdmin}
	case RoleClient:
		return []string{PermissionRead, PermissionWrite}
	default:
		return []string{PermissionRead}
	}
}
