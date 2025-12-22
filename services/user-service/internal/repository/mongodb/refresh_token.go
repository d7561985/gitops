package mongodb

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"gitlab.com/gitops-poc-dzha/user-service/internal/domain"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	ErrRefreshTokenNotFound = errors.New("refresh token not found")
	ErrRefreshTokenExpired  = errors.New("refresh token expired")
)

// RefreshTokenRepository handles refresh token persistence
type RefreshTokenRepository struct {
	collection *mongo.Collection
}

// NewRefreshTokenRepository creates a new refresh token repository
func NewRefreshTokenRepository(db *mongo.Database) *RefreshTokenRepository {
	return &RefreshTokenRepository{
		collection: db.Collection("refresh_tokens"),
	}
}

// EnsureIndexes creates required indexes
func (r *RefreshTokenRepository) EnsureIndexes(ctx context.Context) error {
	indexes := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "token_hash", Value: 1}},
			Options: options.Index().SetUnique(true),
		},
		{
			Keys:    bson.D{{Key: "user_id", Value: 1}},
			Options: options.Index(),
		},
		{
			Keys:    bson.D{{Key: "expires_at", Value: 1}},
			Options: options.Index().SetExpireAfterSeconds(0), // TTL index
		},
	}

	_, err := r.collection.Indexes().CreateMany(ctx, indexes)
	return err
}

// hashToken creates a SHA256 hash of the token
func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

// Create stores a new refresh token
func (r *RefreshTokenRepository) Create(ctx context.Context, token string, userID primitive.ObjectID, sessionID string, ttl time.Duration) error {
	refreshToken := &domain.RefreshToken{
		TokenHash: hashToken(token),
		UserID:    userID,
		SessionID: sessionID,
		ExpiresAt: time.Now().Add(ttl),
		CreatedAt: time.Now(),
	}

	_, err := r.collection.InsertOne(ctx, refreshToken)
	return err
}

// Find finds a refresh token and validates it hasn't expired
func (r *RefreshTokenRepository) Find(ctx context.Context, token string) (*domain.RefreshToken, error) {
	var refreshToken domain.RefreshToken
	err := r.collection.FindOne(ctx, bson.M{"token_hash": hashToken(token)}).Decode(&refreshToken)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return nil, ErrRefreshTokenNotFound
		}
		return nil, err
	}

	if time.Now().After(refreshToken.ExpiresAt) {
		return nil, ErrRefreshTokenExpired
	}

	return &refreshToken, nil
}

// Delete removes a refresh token
func (r *RefreshTokenRepository) Delete(ctx context.Context, token string) error {
	_, err := r.collection.DeleteOne(ctx, bson.M{"token_hash": hashToken(token)})
	return err
}

// DeleteByUserID removes all refresh tokens for a user
func (r *RefreshTokenRepository) DeleteByUserID(ctx context.Context, userID primitive.ObjectID) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"user_id": userID})
	return err
}

// DeleteBySessionID removes refresh token for a specific session
func (r *RefreshTokenRepository) DeleteBySessionID(ctx context.Context, sessionID string) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"session_id": sessionID})
	return err
}
