package main

import (
	"context"
	"log"

	"connectrpc.com/connect"
	"gitlab.com/gitops-poc-dzha/analytics-service/internal/service"

	analyticsv1 "gitlab.com/gitops-poc-dzha/api/gen/analytics-service/go/analytics/v1"
)

// AnalyticsServiceServer implements analyticsv1connect.AnalyticsServiceHandler
type AnalyticsServiceServer struct {
	svc *service.AnalyticsService
}

func NewAnalyticsServiceServer(svc *service.AnalyticsService) *AnalyticsServiceServer {
	return &AnalyticsServiceServer{svc: svc}
}

func (s *AnalyticsServiceServer) GetRTPMetrics(
	ctx context.Context,
	req *connect.Request[analyticsv1.GetRTPMetricsRequest],
) (*connect.Response[analyticsv1.GetRTPMetricsResponse], error) {
	log.Printf("[RPC] GetRTPMetrics: hours=%d", req.Msg.Hours)

	hours := int(req.Msg.Hours)
	if hours <= 0 {
		hours = 1
	}

	metrics := s.svc.GetRTPMetrics(hours)

	return connect.NewResponse(&analyticsv1.GetRTPMetricsResponse{
		PeriodHours:   int32(metrics.PeriodHours),
		OverallRtp:    metrics.OverallRTP,
		RtpThreshold:  &analyticsv1.RTPThreshold{
			Min:    metrics.RTPThreshold.Min,
			Max:    metrics.RTPThreshold.Max,
			Status: metrics.RTPThreshold.Status,
		},
		GameCount:     int32(metrics.GameCount),
		UniquePlayers: int32(metrics.UniquePlayers),
		TotalRevenue:  metrics.TotalRevenue,
		TotalPayouts:  metrics.TotalPayouts,
	}), nil
}

func (s *AnalyticsServiceServer) GetSessionMetrics(
	ctx context.Context,
	req *connect.Request[analyticsv1.GetSessionMetricsRequest],
) (*connect.Response[analyticsv1.GetSessionMetricsResponse], error) {
	log.Printf("[RPC] GetSessionMetrics")

	metrics := s.svc.GetSessionMetrics()

	return connect.NewResponse(&analyticsv1.GetSessionMetricsResponse{
		ActiveSessions: int32(metrics.ActiveSessions),
		AvgDuration:    metrics.AvgDuration,
	}), nil
}

func (s *AnalyticsServiceServer) GetFinancialMetrics(
	ctx context.Context,
	req *connect.Request[analyticsv1.GetFinancialMetricsRequest],
) (*connect.Response[analyticsv1.GetFinancialMetricsResponse], error) {
	log.Printf("[RPC] GetFinancialMetrics: hours=%d", req.Msg.Hours)

	hours := int(req.Msg.Hours)
	if hours <= 0 {
		hours = 24
	}

	metrics := s.svc.GetFinancialMetrics(hours)

	return connect.NewResponse(&analyticsv1.GetFinancialMetricsResponse{
		PeriodHours:     int32(metrics.PeriodHours),
		TotalRevenue:    metrics.TotalRevenue,
		DepositCount:    int32(metrics.DepositCount),
		AvgDeposit:      metrics.AvgDeposit,
		WithdrawalCount: int32(metrics.WithdrawalCount),
		AvgWithdrawal:   metrics.AvgWithdrawal,
	}), nil
}

func (s *AnalyticsServiceServer) RecordGameResult(
	ctx context.Context,
	req *connect.Request[analyticsv1.RecordGameResultRequest],
) (*connect.Response[analyticsv1.RecordGameResultResponse], error) {
	log.Printf("[RPC] RecordGameResult: user=%s bet=%.2f", req.Msg.UserId, req.Msg.Bet)

	s.svc.RecordGameResult(ctx, service.GameResult{
		UserID: req.Msg.UserId,
		Bet:    req.Msg.Bet,
		Payout: req.Msg.Payout,
		Win:    req.Msg.Win,
	})

	return connect.NewResponse(&analyticsv1.RecordGameResultResponse{
		Success: true,
	}), nil
}

func (s *AnalyticsServiceServer) RecordTransaction(
	ctx context.Context,
	req *connect.Request[analyticsv1.RecordTransactionRequest],
) (*connect.Response[analyticsv1.RecordTransactionResponse], error) {
	log.Printf("[RPC] RecordTransaction: user=%s type=%s amount=%.2f", req.Msg.UserId, req.Msg.Type, req.Msg.Amount)

	s.svc.RecordTransaction(ctx, service.Transaction{
		UserID: req.Msg.UserId,
		Type:   req.Msg.Type,
		Amount: req.Msg.Amount,
	})

	return connect.NewResponse(&analyticsv1.RecordTransactionResponse{
		Success: true,
	}), nil
}

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
