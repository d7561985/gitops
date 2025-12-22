<?php

namespace App\Service;

use Psr\Log\LoggerInterface;
use Sentry\SentrySdk;
use Sentry\Tracing\SpanContext;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class IntegrationService
{
    public function __construct(
        private HttpClientInterface $httpClient,
        private LoggerInterface $logger,
        private string $userServiceUrl,
        private string $paymentServiceUrl
    ) {}
    
    public function notifyUserService(string $userId, string $action, array $data = []): bool
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('http.client');
            $context->setDescription('Notify User Service');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            $url = $this->userServiceUrl . '/internal/bonus-claimed';
            
            // Get trace headers for propagation
            $headers = $this->getTraceHeaders();
            
            $response = $this->httpClient->request('POST', $url, [
                'headers' => $headers,
                'json' => [
                    'user_id' => $userId,
                    'action' => $action,
                    'data' => $data
                ]
            ]);
            
            if ($response->getStatusCode() !== 200) {
                $this->logger->error('Failed to notify user service', [
                    'user_id' => $userId,
                    'status_code' => $response->getStatusCode()
                ]);
                return false;
            }
            
            return true;
            
        } catch (\Exception $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::internalError());
            $this->logger->error('Error notifying user service', [
                'user_id' => $userId,
                'error' => $e->getMessage()
            ]);
            return false;
        } finally {
            $childSpan?->finish();
        }
    }
    
    public function notifyPaymentService(string $userId, array $balanceUpdate): bool
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('http.client');
            $context->setDescription('Notify Payment Service');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            $url = $this->paymentServiceUrl . '/internal/balance-update';
            
            // Get trace headers for propagation
            $headers = $this->getTraceHeaders();
            
            $response = $this->httpClient->request('POST', $url, [
                'headers' => $headers,
                'json' => [
                    'user_id' => $userId,
                    'balance' => $balanceUpdate
                ]
            ]);
            
            if ($response->getStatusCode() !== 200) {
                $this->logger->error('Failed to notify payment service', [
                    'user_id' => $userId,
                    'status_code' => $response->getStatusCode()
                ]);
                return false;
            }
            
            return true;
            
        } catch (\Exception $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::internalError());
            $this->logger->error('Error notifying payment service', [
                'user_id' => $userId,
                'error' => $e->getMessage()
            ]);
            return false;
        } finally {
            $childSpan?->finish();
        }
    }
    
    private function getTraceHeaders(): array
    {
        $headers = [
            'Content-Type' => 'application/json',
        ];
        
        // Add Sentry trace headers for distributed tracing
        $span = SentrySdk::getCurrentHub()->getSpan();
        if ($span) {
            $headers['Sentry-Trace'] = $span->toTraceparent();
            $baggage = $span->toBaggage();
            if ($baggage) {
                $headers['Baggage'] = $baggage;
            }
        }
        
        return $headers;
    }
    
    /**
     * Extract trace headers from incoming request
     */
    public static function extractTraceHeaders(Request $request): array
    {
        $headers = [];
        
        if ($request->headers->has('sentry-trace')) {
            $headers['sentry-trace'] = $request->headers->get('sentry-trace');
        }
        
        if ($request->headers->has('baggage')) {
            $headers['baggage'] = $request->headers->get('baggage');
        }
        
        return $headers;
    }
}