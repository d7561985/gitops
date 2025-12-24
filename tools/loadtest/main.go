package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"golang.org/x/time/rate"
)

// ANSI colors
const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorBlue   = "\033[34m"
	colorCyan   = "\033[36m"
	colorGray   = "\033[90m"
	colorBold   = "\033[1m"
)

// Endpoint represents a Connect RPC endpoint
type Endpoint struct {
	Name    string
	URL     string
	Payload map[string]interface{}
}

// Stats holds statistics for an endpoint
type Stats struct {
	Name         string
	Total        int64
	Success      int64
	Errors       int64
	Latencies    []time.Duration
	ErrorDetails map[string]int64
	mu           sync.Mutex
}

func (s *Stats) Add(latency time.Duration, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	atomic.AddInt64(&s.Total, 1)
	if err != nil {
		atomic.AddInt64(&s.Errors, 1)
		errStr := err.Error()
		if len(errStr) > 50 {
			errStr = errStr[:50] + "..."
		}
		s.ErrorDetails[errStr]++
	} else {
		atomic.AddInt64(&s.Success, 1)
		s.Latencies = append(s.Latencies, latency)
	}
}

func (s *Stats) Percentile(p float64) time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.Latencies) == 0 {
		return 0
	}

	sorted := make([]time.Duration, len(s.Latencies))
	copy(sorted, s.Latencies)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })

	idx := int(float64(len(sorted)-1) * p)
	return sorted[idx]
}

func (s *Stats) Avg() time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.Latencies) == 0 {
		return 0
	}

	var sum time.Duration
	for _, l := range s.Latencies {
		sum += l
	}
	return sum / time.Duration(len(s.Latencies))
}

func main() {
	// Flags
	baseURL := flag.String("url", "https://app.demo-poc-01.work", "Base URL")
	rps := flag.Float64("rps", 10, "Requests per second (rate limit)")
	concurrency := flag.Int("c", 5, "Number of parallel workers")
	duration := flag.Duration("d", 30*time.Second, "Test duration")
	userID := flag.String("user", "loadtest-user-1", "User ID for requests")
	bet := flag.Float64("bet", 10.0, "Bet amount for Calculate")
	cpuIntensive := flag.Bool("cpu", false, "Enable CPU intensive mode")
	flag.Parse()

	// Endpoints
	endpoints := []Endpoint{
		{
			Name: "GameEngine/Calculate",
			URL:  *baseURL + "/api/gameconnect/game.v1.GameEngineService/Calculate",
			Payload: map[string]interface{}{
				"userId":       *userID,
				"bet":          *bet,
				"cpuIntensive": *cpuIntensive,
			},
		},
		{
			Name: "BonusService/GetProgress",
			URL:  *baseURL + "/api/bonusconnect/wager.v1.BonusService/GetProgress",
			Payload: map[string]interface{}{
				"userId": *userID,
			},
		},
	}

	// Print banner
	printBanner(*baseURL, *rps, *concurrency, *duration)

	// Context with cancel
	ctx, cancel := context.WithTimeout(context.Background(), *duration)
	defer cancel()

	// Handle interrupt
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Printf("\n%s⚠ Interrupted, stopping...%s\n", colorYellow, colorReset)
		cancel()
	}()

	// Rate limiter
	limiter := rate.NewLimiter(rate.Limit(*rps), int(*rps))

	// HTTP client
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	// Stats per endpoint
	stats := make(map[string]*Stats)
	for _, ep := range endpoints {
		stats[ep.Name] = &Stats{
			Name:         ep.Name,
			ErrorDetails: make(map[string]int64),
		}
	}

	// Start time
	startTime := time.Now()

	// Progress channel
	progressCh := make(chan struct{}, 1000)

	// Start workers
	var wg sync.WaitGroup
	for i := 0; i < *concurrency; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			worker(ctx, client, limiter, endpoints, stats, progressCh)
		}(i)
	}

	// Progress reporter
	go progressReporter(ctx, startTime, *duration, stats, progressCh)

	// Wait for workers
	wg.Wait()
	close(progressCh)

	// Print results
	printResults(stats, time.Since(startTime))
}

func worker(ctx context.Context, client *http.Client, limiter *rate.Limiter, endpoints []Endpoint, stats map[string]*Stats, progressCh chan<- struct{}) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Rate limit
		if err := limiter.Wait(ctx); err != nil {
			return
		}

		// Round-robin endpoints
		for _, ep := range endpoints {
			select {
			case <-ctx.Done():
				return
			default:
			}

			latency, err := callEndpoint(ctx, client, ep)
			stats[ep.Name].Add(latency, err)

			select {
			case progressCh <- struct{}{}:
			default:
			}
		}
	}
}

func callEndpoint(ctx context.Context, client *http.Client, ep Endpoint) (time.Duration, error) {
	payload, _ := json.Marshal(ep.Payload)

	req, err := http.NewRequestWithContext(ctx, "POST", ep.URL, bytes.NewReader(payload))
	if err != nil {
		return 0, err
	}

	// Connect RPC headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connect-Protocol-Version", "1")

	start := time.Now()
	resp, err := client.Do(req)
	latency := time.Since(start)

	if err != nil {
		return latency, err
	}
	defer resp.Body.Close()

	// Read body
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return latency, fmt.Errorf("HTTP %d: %s", resp.StatusCode, truncate(string(body), 100))
	}

	return latency, nil
}

func progressReporter(ctx context.Context, startTime time.Time, duration time.Duration, stats map[string]*Stats, progressCh <-chan struct{}) {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			elapsed := time.Since(startTime)
			remaining := duration - elapsed
			if remaining < 0 {
				remaining = 0
			}

			// Calculate totals
			var total, success, errors int64
			for _, s := range stats {
				total += atomic.LoadInt64(&s.Total)
				success += atomic.LoadInt64(&s.Success)
				errors += atomic.LoadInt64(&s.Errors)
			}

			// Progress bar
			progress := float64(elapsed) / float64(duration)
			if progress > 1 {
				progress = 1
			}
			barWidth := 30
			filled := int(progress * float64(barWidth))
			bar := fmt.Sprintf("[%s%s%s%s]",
				colorGreen, repeatChar('█', filled),
				repeatChar('░', barWidth-filled), colorReset)

			// Current RPS
			rps := float64(total) / elapsed.Seconds()

			// Clear line and print progress
			fmt.Printf("\r%s%s %.0f%% %s│ %sReqs:%s %d │ %sOK:%s %d │ %sErr:%s %d │ %sRPS:%s %.1f │ %sRemaining:%s %s   ",
				colorBold, bar, progress*100, colorReset,
				colorCyan, colorReset, total,
				colorGreen, colorReset, success,
				colorRed, colorReset, errors,
				colorYellow, colorReset, rps,
				colorGray, colorReset, remaining.Truncate(time.Second))
		}
	}
}

func printBanner(baseURL string, rps float64, concurrency int, duration time.Duration) {
	fmt.Printf(`
%s╔══════════════════════════════════════════════════════════════╗
║           %sConnect RPC Load Tester%s                             ║
╚══════════════════════════════════════════════════════════════╝%s

%s▸ Target:%s    %s
%s▸ Rate:%s      %.1f req/s
%s▸ Workers:%s   %d parallel
%s▸ Duration:%s  %s

%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s
`,
		colorCyan, colorBold, colorCyan, colorReset,
		colorBlue, colorReset, baseURL,
		colorBlue, colorReset, rps,
		colorBlue, colorReset, concurrency,
		colorBlue, colorReset, duration,
		colorGray, colorReset,
	)
}

func printResults(stats map[string]*Stats, totalTime time.Duration) {
	fmt.Printf("\n\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n", colorGray, colorReset)
	fmt.Printf("%s%s                        RESULTS%s\n", colorBold, colorCyan, colorReset)
	fmt.Printf("%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n\n", colorGray, colorReset)

	var grandTotal, grandSuccess, grandErrors int64

	// Sort endpoints by name
	names := make([]string, 0, len(stats))
	for name := range stats {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		s := stats[name]
		total := atomic.LoadInt64(&s.Total)
		success := atomic.LoadInt64(&s.Success)
		errors := atomic.LoadInt64(&s.Errors)

		grandTotal += total
		grandSuccess += success
		grandErrors += errors

		successRate := float64(0)
		if total > 0 {
			successRate = float64(success) / float64(total) * 100
		}

		statusColor := colorGreen
		if successRate < 99 {
			statusColor = colorYellow
		}
		if successRate < 95 {
			statusColor = colorRed
		}

		fmt.Printf("%s▸ %s%s%s\n", colorBold, colorCyan, name, colorReset)
		fmt.Printf("  │ Requests:    %d total, %s%d success%s, %s%d errors%s\n",
			total,
			colorGreen, success, colorReset,
			colorRed, errors, colorReset)
		fmt.Printf("  │ Success:     %s%.2f%%%s\n", statusColor, successRate, colorReset)

		if len(s.Latencies) > 0 {
			fmt.Printf("  │ Latency:\n")
			fmt.Printf("  │   %sAvg:%s    %s\n", colorGray, colorReset, s.Avg().Truncate(time.Microsecond))
			fmt.Printf("  │   %sp50:%s    %s\n", colorGray, colorReset, s.Percentile(0.50).Truncate(time.Microsecond))
			fmt.Printf("  │   %sp90:%s    %s\n", colorGray, colorReset, s.Percentile(0.90).Truncate(time.Microsecond))
			fmt.Printf("  │   %sp99:%s    %s\n", colorGray, colorReset, s.Percentile(0.99).Truncate(time.Microsecond))
			fmt.Printf("  │   %sMax:%s    %s\n", colorGray, colorReset, s.Percentile(1.0).Truncate(time.Microsecond))
		}

		if len(s.ErrorDetails) > 0 {
			fmt.Printf("  │ Errors:\n")
			for errMsg, count := range s.ErrorDetails {
				fmt.Printf("  │   %s%s%s: %d\n", colorRed, errMsg, colorReset, count)
			}
		}
		fmt.Println()
	}

	// Summary
	fmt.Printf("%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n", colorGray, colorReset)
	fmt.Printf("%sSUMMARY%s\n", colorBold, colorReset)
	fmt.Printf("  Total requests:  %d\n", grandTotal)
	fmt.Printf("  Total time:      %s\n", totalTime.Truncate(time.Millisecond))
	fmt.Printf("  Throughput:      %.2f req/s\n", float64(grandTotal)/totalTime.Seconds())

	grandSuccessRate := float64(0)
	if grandTotal > 0 {
		grandSuccessRate = float64(grandSuccess) / float64(grandTotal) * 100
	}

	statusColor := colorGreen
	if grandSuccessRate < 99 {
		statusColor = colorYellow
	}
	if grandSuccessRate < 95 {
		statusColor = colorRed
	}
	fmt.Printf("  Success rate:    %s%.2f%%%s\n", statusColor, grandSuccessRate, colorReset)
	fmt.Printf("%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n", colorGray, colorReset)
}

func repeatChar(c rune, n int) string {
	if n <= 0 {
		return ""
	}
	result := make([]rune, n)
	for i := range result {
		result[i] = c
	}
	return string(result)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

// Suppress unused import warning
var _ = math.Max
