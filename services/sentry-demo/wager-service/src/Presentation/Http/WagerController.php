<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use App\Application\DTO\ValidateWagerRequest;
use App\Application\DTO\PlaceWagerRequest;
use App\Application\DTO\GetHistoryRequest;
use App\Application\UseCase\Wager\ValidateWagerUseCase;
use App\Application\UseCase\Wager\PlaceWagerUseCase;
use App\Application\UseCase\Wager\GetWagerHistoryUseCase;
use App\Service\WagerService;
use Psr\Log\LoggerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

/**
 * HTTP REST Controller for Wager operations
 * Uses the SAME use cases as Connect controller!
 */
#[Route('/wager')]
class WagerController extends AbstractController
{
    public function __construct(
        private ValidateWagerUseCase $validateWager,
        private PlaceWagerUseCase $placeWager,
        private GetWagerHistoryUseCase $getHistory,
        private WagerService $wagerService,
        private LoggerInterface $logger
    ) {}

    #[Route('/validate', name: 'wager_validate', methods: ['POST'])]
    public function validate(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        $userId = $data['user_id'] ?? null;
        $amount = $data['amount'] ?? null;
        $gameId = $data['game_id'] ?? null;

        if (!$userId || !$amount || !$gameId) {
            return $this->json([
                'error' => 'user_id, amount, and game_id are required'
            ], 400);
        }

        try {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });

            $result = $this->validateWager->execute(new ValidateWagerRequest(
                userId: $userId,
                amount: (float)$amount,
                gameId: $gameId
            ));

            // Return snake_case for REST API compatibility
            return $this->json($result->toSnakeCase());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/place', name: 'wager_place', methods: ['POST'])]
    public function place(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        $validationData = $data['validation_data'] ?? null;
        $gameResult = $data['game_result'] ?? null;
        $payout = $data['payout'] ?? 0;

        if (!$validationData || !$gameResult) {
            return $this->json([
                'error' => 'validation_data and game_result are required'
            ], 400);
        }

        if (!in_array($gameResult, ['win', 'lose'])) {
            return $this->json([
                'error' => 'game_result must be win or lose'
            ], 400);
        }

        try {
            $userId = $validationData['user_id'] ?? null;
            if ($userId) {
                \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                    $scope->setUser(['id' => $userId]);
                });
            }

            $result = $this->placeWager->execute(new PlaceWagerRequest(
                validationData: $validationData,
                gameResult: $gameResult,
                payout: (float)$payout
            ));

            return $this->json($result->toSnakeCase());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/history/{userId}', name: 'wager_history', methods: ['GET'])]
    public function history(string $userId, Request $request): JsonResponse
    {
        try {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });

            $limit = $request->query->getInt('limit', 10);

            $result = $this->getHistory->execute(new GetHistoryRequest(
                userId: $userId,
                limit: $limit
            ));

            return $this->json($result->toSnakeCase());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/demo/error/{errorType}', name: 'wager_demo_error', methods: ['GET'])]
    public function demoError(string $errorType): JsonResponse
    {
        try {
            $this->wagerService->triggerDemoError($errorType);
            return $this->json(['message' => 'Error should have been triggered']);
        } catch (\Exception $e) {
            \Sentry\captureException($e);
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName(),
                'demo' => true
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/test/sentry', name: 'test_sentry', methods: ['GET'])]
    public function testSentry(): JsonResponse
    {
        $this->logger->info('Testing Sentry integration');
        \Sentry\captureException(new \RuntimeException('Test exception for Sentry'));
        \Sentry\captureMessage('Test message from Wager Service', \Sentry\Severity::info());

        return $this->json([
            'message' => 'Test exception and message sent to Sentry',
            'dsn_configured' => !empty($_ENV['SENTRY_DSN'])
        ]);
    }
}
