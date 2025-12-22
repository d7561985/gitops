<?php

namespace App\EventSubscriber;

use Sentry\Event;
use Sentry\EventHint;
use Sentry\SentrySdk;
use Sentry\Tracing\SpanContext;
use Sentry\Tracing\TransactionContext;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\KernelEvents;

class SentrySubscriber implements EventSubscriberInterface
{
    private array $transactions = [];
    
    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::REQUEST => ['onKernelRequest', 1000],
            KernelEvents::RESPONSE => ['onKernelResponse', -1000],
            KernelEvents::EXCEPTION => ['onKernelException', 0],
        ];
    }
    
    public function onKernelRequest(RequestEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }
        
        $request = $event->getRequest();
        
        // Extract trace headers
        $sentryTrace = $request->headers->get('sentry-trace', '');
        $baggage = $request->headers->get('baggage', '');
        
        // Determine transaction name
        $route = $request->attributes->get('_route', 'unknown');
        $method = $request->getMethod();
        $transactionName = "$method /$route";
        
        // Start or continue transaction
        if ($sentryTrace) {
            $transactionContext = TransactionContext::fromHeaders(
                $sentryTrace,
                $baggage
            );
            $transactionContext->setName($transactionName);
            $transactionContext->setOp('http.server');
        } else {
            $transactionContext = new TransactionContext();
            $transactionContext->setName($transactionName);
            $transactionContext->setOp('http.server');
        }
        
        $transaction = SentrySdk::getCurrentHub()->startTransaction($transactionContext);
        SentrySdk::getCurrentHub()->setSpan($transaction);
        
        // Store for later
        $this->transactions[spl_object_id($request)] = $transaction;
        
        // Set request data
        $transaction->setData([
            'http.request.method' => $method,
            'http.request.path' => $request->getPathInfo(),
            'http.request.query' => $request->query->all(),
            'http.request.size' => $request->headers->get('content-length', 0),
        ]);
        
        // Add user context if available
        if ($userId = $request->attributes->get('userId')) {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });
        }
    }
    
    public function onKernelResponse(ResponseEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }
        
        $request = $event->getRequest();
        $response = $event->getResponse();
        $requestId = spl_object_id($request);
        
        if (!isset($this->transactions[$requestId])) {
            return;
        }
        
        $transaction = $this->transactions[$requestId];
        unset($this->transactions[$requestId]);
        
        // Set response data
        $transaction->setData([
            'http.response.status_code' => $response->getStatusCode(),
            'http.response.size' => strlen($response->getContent()),
        ]);
        
        // Set status based on HTTP code
        $statusCode = $response->getStatusCode();
        if ($statusCode >= 200 && $statusCode < 400) {
            $transaction->setStatus(\Sentry\Tracing\SpanStatus::ok());
        } elseif ($statusCode >= 400 && $statusCode < 500) {
            $transaction->setStatus(\Sentry\Tracing\SpanStatus::invalidArgument());
        } else {
            $transaction->setStatus(\Sentry\Tracing\SpanStatus::internalError());
        }
        
        // Finish transaction
        $transaction->finish();
    }
    
    public function onKernelException(ExceptionEvent $event): void
    {
        $exception = $event->getThrowable();
        $request = $event->getRequest();
        $requestId = spl_object_id($request);
        
        // Add exception context
        \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($request) {
            $scope->setContext('request', [
                'method' => $request->getMethod(),
                'url' => $request->getUri(),
                'ip' => $request->getClientIp(),
                'user_agent' => $request->headers->get('User-Agent'),
            ]);
        });
        
        // Mark transaction as failed if exists
        if (isset($this->transactions[$requestId])) {
            $transaction = $this->transactions[$requestId];
            $transaction->setStatus(\Sentry\Tracing\SpanStatus::internalError());
        }
    }
    
    /**
     * Custom transaction name formatting
     */
    public static function beforeSendTransaction(Event $event, ?EventHint $hint): ?Event
    {
        // Clean up transaction names
        $transaction = $event->getTransaction();
        if ($transaction) {
            // Remove parameter values from URLs
            $transaction = preg_replace('/\/\d+/', '/{id}', $transaction);
            $transaction = preg_replace('/\/[a-f0-9\-]{36}/', '/{uuid}', $transaction);
            $event->setTransaction($transaction);
        }
        
        // Add custom context
        $event->setContext('wager_service', [
            'version' => $_ENV['APP_VERSION'] ?? 'unknown',
            'environment' => $_ENV['APP_ENV'] ?? 'unknown',
        ]);
        
        return $event;
    }
}