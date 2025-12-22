<?php

declare(strict_types=1);

namespace App\Application\UseCase\Bonus;

use App\Application\DTO\GetProgressRequest;
use App\Application\DTO\GetProgressResponse;
use App\Service\BonusService;

/**
 * Get Bonus Progress Use Case
 */
final class GetBonusProgressUseCase
{
    public function __construct(
        private BonusService $bonusService
    ) {}

    public function execute(GetProgressRequest $request): GetProgressResponse
    {
        $result = $this->bonusService->getProgress($request->userId);

        $hasBonus = $result['has_active_bonus'];
        $bonus = $result['bonus'] ?? null;
        $balance = $result['balance'];

        return new GetProgressResponse(
            hasActiveBonus: $hasBonus,
            bonusBalance: $balance['bonus'],
            realBalance: $balance['real'],
            progressPercent: $bonus['progress_percentage'] ?? 0,
            wageringRequired: $bonus['wagering_required'] ?? 0,
            wageredAmount: $bonus['wagering_completed'] ?? 0,
            remaining: ($bonus['wagering_required'] ?? 0) - ($bonus['wagering_completed'] ?? 0),
            canConvert: $bonus['status'] === 'completed' ?? false,
            expiresAt: $bonus['created_at'] ?? null
        );
    }
}
