<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use App\Application\DTO\ClaimBonusRequest;
use App\Application\DTO\GetProgressRequest;
use App\Application\DTO\ConvertBonusRequest;
use App\Application\UseCase\Bonus\ClaimBonusUseCase;
use App\Application\UseCase\Bonus\GetBonusProgressUseCase;
use App\Application\UseCase\Bonus\ConvertBonusUseCase;
use App\Service\BonusService;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

/**
 * HTTP REST Controller for Bonus operations
 * Uses the SAME use cases as Connect controller!
 */
#[Route('/bonus')]
class BonusController extends AbstractController
{
    public function __construct(
        private ClaimBonusUseCase $claimBonus,
        private GetBonusProgressUseCase $getProgress,
        private ConvertBonusUseCase $convertBonus,
        private BonusService $bonusService
    ) {}

    #[Route('/claim', name: 'bonus_claim', methods: ['POST'])]
    public function claim(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $userId = $data['user_id'] ?? null;

        if (!$userId) {
            return $this->json(['error' => 'user_id is required'], 400);
        }

        try {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });

            $result = $this->claimBonus->execute(
                new ClaimBonusRequest(userId: $userId),
                $request
            );

            return $this->json($result->toArray());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/progress/{userId}', name: 'bonus_progress', methods: ['GET'])]
    public function progress(string $userId): JsonResponse
    {
        try {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });

            $result = $this->getProgress->execute(
                new GetProgressRequest(userId: $userId)
            );

            return $this->json($result->toArray());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/convert/{userId}', name: 'bonus_convert', methods: ['POST'])]
    public function convert(string $userId): JsonResponse
    {
        try {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($userId) {
                $scope->setUser(['id' => $userId]);
            });

            $result = $this->convertBonus->execute(
                new ConvertBonusRequest(userId: $userId)
            );

            return $this->json($result->toArray());
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName()
            ], $e->getCode() ?: 500);
        }
    }

    #[Route('/demo/error/{errorType}', name: 'bonus_demo_error', methods: ['GET'])]
    public function demoError(string $errorType): JsonResponse
    {
        try {
            $this->bonusService->triggerDemoError($errorType);
            return $this->json(['message' => 'Error should have been triggered']);
        } catch (\Exception $e) {
            return $this->json([
                'error' => $e->getMessage(),
                'type' => (new \ReflectionClass($e))->getShortName(),
                'demo' => true
            ], $e->getCode() ?: 500);
        }
    }
}
