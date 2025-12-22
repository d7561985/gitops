<?php

declare(strict_types=1);

namespace App\Application\UseCase\Wager;

use App\Application\DTO\PlaceWagerRequest;
use App\Application\DTO\PlaceWagerResponse;
use App\Application\DTO\WageringProgressDTO;
use App\Service\WagerService;

/**
 * Place Wager Use Case
 */
final class PlaceWagerUseCase
{
    public function __construct(
        private WagerService $wagerService
    ) {}

    public function execute(PlaceWagerRequest $request): PlaceWagerResponse
    {
        $result = $this->wagerService->placeWager(
            $request->validationData,
            $request->gameResult,
            $request->payout
        );

        $wageringProgress = null;
        if (isset($result['wagering_progress'])) {
            $wp = $result['wagering_progress'];
            $wageringProgress = new WageringProgressDTO(
                progressPercent: $wp['percentage'] ?? 0,
                remaining: ($wp['required'] ?? 0) - ($wp['completed'] ?? 0),
                canConvert: $wp['is_complete'] ?? false,
                totalRequired: $wp['required'] ?? 0,
                totalWagered: $wp['completed'] ?? 0
            );
        }

        return new PlaceWagerResponse(
            success: $result['success'],
            wagerId: $result['wager_id'],
            wageringProgress: $wageringProgress
        );
    }
}
