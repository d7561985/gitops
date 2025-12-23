package service

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"connectrpc.com/connect"
	"github.com/redis/go-redis/v9"
)

// GameResult represents a recorded game result
type GameResult struct {
	UserID  string    `json:"user_id"`
	Bet     float64   `json:"bet"`
	Payout  float64   `json:"payout"`
	Win     bool      `json:"win"`
	Time    time.Time `json:"time"`
}

// Transaction represents a financial transaction
type Transaction struct {
	UserID string    `json:"user_id"`
	Type   string    `json:"type"` // "deposit" or "withdrawal"
	Amount float64   `json:"amount"`
	Time   time.Time `json:"time"`
}

// AnalyticsService handles business metrics
type AnalyticsService struct {
	redis *redis.Client

	// In-memory storage (fallback when Redis not available)
	mu           sync.RWMutex
	gameResults  []GameResult
	transactions []Transaction
	sessions     map[string]time.Time // userID -> session start time
}

// NewAnalyticsService creates a new analytics service
func NewAnalyticsService(rdb *redis.Client) *AnalyticsService {
	svc := &AnalyticsService{
		redis:        rdb,
		gameResults:  make([]GameResult, 0),
		transactions: make([]Transaction, 0),
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
		win := rand.Float64() < 0.45   // ~45% win rate
		var payout float64
		if win {
			payout = bet * (1 + rand.Float64()*2) // 1x-3x multiplier
		}

		s.gameResults = append(s.gameResults, GameResult{
			UserID:  fmt.Sprintf("user_%d", rand.Intn(20)),
			Bet:     bet,
			Payout:  payout,
			Win:     win,
			Time:    now.Add(-time.Duration(rand.Intn(24*60)) * time.Minute),
		})
	}

	// Generate transactions
	for i := 0; i < 50; i++ {
		txType := "deposit"
		if rand.Float64() < 0.3 {
			txType = "withdrawal"
		}

		s.transactions = append(s.transactions, Transaction{
			UserID: fmt.Sprintf("user_%d", rand.Intn(20)),
			Type:   txType,
			Amount: 50 + rand.Float64()*450, // $50-$500
			Time:   now.Add(-time.Duration(rand.Intn(24*60)) * time.Minute),
		})
	}

	// Generate active sessions
	for i := 0; i < 15; i++ {
		userID := fmt.Sprintf("user_%d", i)
		s.sessions[userID] = now.Add(-time.Duration(rand.Intn(60)) * time.Minute)
	}
}

// Handler returns the Connect handler path and handler
func (s *AnalyticsService) Handler() (string, http.Handler) {
	mux := http.NewServeMux()

	// REST endpoints for frontend compatibility
	mux.HandleFunc("/api/v1/business-metrics/rtp", s.handleRTPMetrics)
	mux.HandleFunc("/api/v1/business-metrics/sessions", s.handleSessionMetrics)
	mux.HandleFunc("/api/v1/business-metrics/financial", s.handleFinancialMetrics)

	// Connect/gRPC endpoints (for future use)
	mux.HandleFunc("/analytics.v1.AnalyticsService/GetRTPMetrics", s.handleConnectRTP)
	mux.HandleFunc("/analytics.v1.AnalyticsService/GetSessionMetrics", s.handleConnectSessions)
	mux.HandleFunc("/analytics.v1.AnalyticsService/GetFinancialMetrics", s.handleConnectFinancial)
	mux.HandleFunc("/analytics.v1.AnalyticsService/RecordGameResult", s.handleRecordGame)
	mux.HandleFunc("/analytics.v1.AnalyticsService/RecordTransaction", s.handleRecordTransaction)

	return "/", mux
}

// REST Handlers (for current frontend)

func (s *AnalyticsService) handleRTPMetrics(w http.ResponseWriter, r *http.Request) {
	hours := 1
	if h := r.URL.Query().Get("hours"); h != "" {
		fmt.Sscanf(h, "%d", &hours)
	}

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

	response := map[string]interface{}{
		"period_hours": hours,
		"overall_rtp":  rtp,
		"rtp_threshold": map[string]interface{}{
			"min":    92.0,
			"max":    96.0,
			"status": status,
		},
		"game_count":     gameCount,
		"unique_players": len(uniquePlayers),
		"total_revenue":  totalBets,
		"total_payouts":  totalPayouts,
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(response)
}

func (s *AnalyticsService) handleSessionMetrics(w http.ResponseWriter, r *http.Request) {
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

	response := map[string]interface{}{
		"active_sessions": activeCount,
		"avg_duration":    avgDuration,
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(response)
}

func (s *AnalyticsService) handleFinancialMetrics(w http.ResponseWriter, r *http.Request) {
	hours := 24
	if h := r.URL.Query().Get("hours"); h != "" {
		fmt.Sscanf(h, "%d", &hours)
	}

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

	response := map[string]interface{}{
		"period_hours":     hours,
		"total_revenue":    totalRevenue,
		"deposit_count":    depositCount,
		"avg_deposit":      avgDeposit,
		"withdrawal_count": withdrawalCount,
		"avg_withdrawal":   avgWithdrawal,
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(response)
}

// Connect/gRPC Handlers (JSON-based for simplicity)

func (s *AnalyticsService) handleConnectRTP(w http.ResponseWriter, r *http.Request) {
	s.handleRTPMetrics(w, r)
}

func (s *AnalyticsService) handleConnectSessions(w http.ResponseWriter, r *http.Request) {
	s.handleSessionMetrics(w, r)
}

func (s *AnalyticsService) handleConnectFinancial(w http.ResponseWriter, r *http.Request) {
	s.handleFinancialMetrics(w, r)
}

func (s *AnalyticsService) handleRecordGame(w http.ResponseWriter, r *http.Request) {
	if r.Method == "OPTIONS" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.WriteHeader(http.StatusOK)
		return
	}

	var req struct {
		UserID string  `json:"user_id"`
		Bet    float64 `json:"bet"`
		Payout float64 `json:"payout"`
		Win    bool    `json:"win"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	s.gameResults = append(s.gameResults, GameResult{
		UserID: req.UserID,
		Bet:    req.Bet,
		Payout: req.Payout,
		Win:    req.Win,
		Time:   time.Now(),
	})
	s.mu.Unlock()

	// Store in Redis if available
	if s.redis != nil {
		ctx := context.Background()
		data, _ := json.Marshal(req)
		s.redis.LPush(ctx, "analytics:games", data)
		s.redis.LTrim(ctx, "analytics:games", 0, 999) // Keep last 1000
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

func (s *AnalyticsService) handleRecordTransaction(w http.ResponseWriter, r *http.Request) {
	if r.Method == "OPTIONS" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.WriteHeader(http.StatusOK)
		return
	}

	var req struct {
		UserID string  `json:"user_id"`
		Type   string  `json:"type"`
		Amount float64 `json:"amount"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	s.transactions = append(s.transactions, Transaction{
		UserID: req.UserID,
		Type:   req.Type,
		Amount: req.Amount,
		Time:   time.Now(),
	})
	s.mu.Unlock()

	// Store in Redis if available
	if s.redis != nil {
		ctx := context.Background()
		data, _ := json.Marshal(req)
		s.redis.LPush(ctx, "analytics:transactions", data)
		s.redis.LTrim(ctx, "analytics:transactions", 0, 999)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(map[string]bool{"success": true})
}

// Unused import fix
var _ = connect.CodeUnknown
