package service

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
)

// GameResult represents a recorded game result
type GameResult struct {
	UserID string  `json:"user_id"`
	Bet    float64 `json:"bet"`
	Payout float64 `json:"payout"`
	Win    bool    `json:"win"`
}

// Transaction represents a financial transaction
type Transaction struct {
	UserID string  `json:"user_id"`
	Type   string  `json:"type"` // "deposit" or "withdrawal"
	Amount float64 `json:"amount"`
}

// RTPMetrics contains RTP calculation results
type RTPMetrics struct {
	PeriodHours   int
	OverallRTP    float64
	RTPThreshold  RTPThreshold
	GameCount     int
	UniquePlayers int
	TotalRevenue  float64
	TotalPayouts  float64
}

// RTPThreshold defines acceptable RTP boundaries
type RTPThreshold struct {
	Min    float64
	Max    float64
	Status string
}

// SessionMetrics contains session statistics
type SessionMetrics struct {
	ActiveSessions int
	AvgDuration    float64
}

// FinancialMetrics contains financial statistics
type FinancialMetrics struct {
	PeriodHours     int
	TotalRevenue    float64
	DepositCount    int
	AvgDeposit      float64
	WithdrawalCount int
	AvgWithdrawal   float64
}

// gameRecord stores game result with timestamp
type gameRecord struct {
	GameResult
	Time time.Time
}

// transactionRecord stores transaction with timestamp
type transactionRecord struct {
	Transaction
	Time time.Time
}

// AnalyticsService handles business metrics
type AnalyticsService struct {
	redis *redis.Client

	// In-memory storage (fallback when Redis not available)
	mu           sync.RWMutex
	gameResults  []gameRecord
	transactions []transactionRecord
	sessions     map[string]time.Time // userID -> session start time
}

// NewAnalyticsService creates a new analytics service
func NewAnalyticsService(rdb *redis.Client) *AnalyticsService {
	svc := &AnalyticsService{
		redis:        rdb,
		gameResults:  make([]gameRecord, 0),
		transactions: make([]transactionRecord, 0),
		sessions:     make(map[string]time.Time),
	}

	// Generate some initial demo data
	svc.generateDemoData()

	return svc
}

// generateDemoData creates realistic demo data
func (s *AnalyticsService) generateDemoData() {
	now := time.Now()

	// Generate last 24 hours of game results
	for i := 0; i < 100; i++ {
		bet := 10 + rand.Float64()*90 // $10-$100 bets
		win := rand.Float64() < 0.45  // ~45% win rate
		var payout float64
		if win {
			payout = bet * (1 + rand.Float64()*2) // 1x-3x multiplier
		}

		s.gameResults = append(s.gameResults, gameRecord{
			GameResult: GameResult{
				UserID: fmt.Sprintf("user_%d", rand.Intn(20)),
				Bet:    bet,
				Payout: payout,
				Win:    win,
			},
			Time: now.Add(-time.Duration(rand.Intn(24*60)) * time.Minute),
		})
	}

	// Generate transactions
	for i := 0; i < 50; i++ {
		txType := "deposit"
		if rand.Float64() < 0.3 {
			txType = "withdrawal"
		}

		s.transactions = append(s.transactions, transactionRecord{
			Transaction: Transaction{
				UserID: fmt.Sprintf("user_%d", rand.Intn(20)),
				Type:   txType,
				Amount: 50 + rand.Float64()*450, // $50-$500
			},
			Time: now.Add(-time.Duration(rand.Intn(24*60)) * time.Minute),
		})
	}

	// Generate active sessions
	for i := 0; i < 15; i++ {
		userID := fmt.Sprintf("user_%d", i)
		s.sessions[userID] = now.Add(-time.Duration(rand.Intn(60)) * time.Minute)
	}
}

// GetRTPMetrics calculates RTP metrics for the given time period
func (s *AnalyticsService) GetRTPMetrics(hours int) RTPMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	cutoff := time.Now().Add(-time.Duration(hours) * time.Hour)

	var totalBets, totalPayouts float64
	var gameCount int
	uniquePlayers := make(map[string]bool)

	for _, g := range s.gameResults {
		if g.Time.After(cutoff) {
			totalBets += g.Bet
			totalPayouts += g.Payout
			gameCount++
			uniquePlayers[g.UserID] = true
		}
	}

	var rtp float64
	if totalBets > 0 {
		rtp = (totalPayouts / totalBets) * 100
	}

	status := "normal"
	if rtp < 90 || rtp > 98 {
		status = "anomaly"
	}

	return RTPMetrics{
		PeriodHours: hours,
		OverallRTP:  rtp,
		RTPThreshold: RTPThreshold{
			Min:    92.0,
			Max:    96.0,
			Status: status,
		},
		GameCount:     gameCount,
		UniquePlayers: len(uniquePlayers),
		TotalRevenue:  totalBets,
		TotalPayouts:  totalPayouts,
	}
}

// GetSessionMetrics returns current session statistics
func (s *AnalyticsService) GetSessionMetrics() SessionMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	now := time.Now()
	var totalDuration float64
	activeCount := 0

	for _, startTime := range s.sessions {
		duration := now.Sub(startTime).Seconds()
		totalDuration += duration
		activeCount++
	}

	avgDuration := 0.0
	if activeCount > 0 {
		avgDuration = totalDuration / float64(activeCount)
	}

	return SessionMetrics{
		ActiveSessions: activeCount,
		AvgDuration:    avgDuration,
	}
}

// GetFinancialMetrics calculates financial metrics for the given time period
func (s *AnalyticsService) GetFinancialMetrics(hours int) FinancialMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	cutoff := time.Now().Add(-time.Duration(hours) * time.Hour)

	var totalRevenue, totalDeposits, totalWithdrawals float64
	var depositCount, withdrawalCount int

	for _, tx := range s.transactions {
		if tx.Time.After(cutoff) {
			if tx.Type == "deposit" {
				totalDeposits += tx.Amount
				depositCount++
			} else {
				totalWithdrawals += tx.Amount
				withdrawalCount++
			}
		}
	}

	// Revenue from games
	for _, g := range s.gameResults {
		if g.Time.After(cutoff) {
			totalRevenue += g.Bet - g.Payout // House edge
		}
	}

	avgDeposit := 0.0
	if depositCount > 0 {
		avgDeposit = totalDeposits / float64(depositCount)
	}

	avgWithdrawal := 0.0
	if withdrawalCount > 0 {
		avgWithdrawal = totalWithdrawals / float64(withdrawalCount)
	}

	return FinancialMetrics{
		PeriodHours:     hours,
		TotalRevenue:    totalRevenue,
		DepositCount:    depositCount,
		AvgDeposit:      avgDeposit,
		WithdrawalCount: withdrawalCount,
		AvgWithdrawal:   avgWithdrawal,
	}
}

// RecordGameResult stores a new game result
func (s *AnalyticsService) RecordGameResult(ctx context.Context, result GameResult) {
	s.mu.Lock()
	s.gameResults = append(s.gameResults, gameRecord{
		GameResult: result,
		Time:       time.Now(),
	})
	s.mu.Unlock()

	// Store in Redis if available
	if s.redis != nil {
		data, _ := json.Marshal(result)
		s.redis.LPush(ctx, "analytics:games", data)
		s.redis.LTrim(ctx, "analytics:games", 0, 999) // Keep last 1000
	}
}

// RecordTransaction stores a new transaction
func (s *AnalyticsService) RecordTransaction(ctx context.Context, tx Transaction) {
	s.mu.Lock()
	s.transactions = append(s.transactions, transactionRecord{
		Transaction: tx,
		Time:        time.Now(),
	})
	s.mu.Unlock()

	// Store in Redis if available
	if s.redis != nil {
		data, _ := json.Marshal(tx)
		s.redis.LPush(ctx, "analytics:transactions", data)
		s.redis.LTrim(ctx, "analytics:transactions", 0, 999)
	}
}
