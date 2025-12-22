<?php

declare(strict_types=1);

namespace App\Application\UseCase\Bonus;

use App\Application\DTO\ClaimBonusRequest;
use App\Application\DTO\ClaimBonusResponse;
use App\Service\BonusService;
use Symfony\Component\HttpFoundation\Request;

/**
 * Claim Bonus Use Case
 */
final class ClaimBonusUseCase
{
    public function __construct(
        private BonusService $bonusService
    ) {}

    public function execute(ClaimBonusRequest $request, ?Request $httpRequest = null): ClaimBonusResponse
    {
        // Create a minimal Request if not provided
        $httpRequest = $httpRequest ?? new Request();

        try {
            $result = $this->bonusService->claimWelcomeBonus(
                $request->userId,
                $httpRequest
            );

            return new ClaimBonusResponse(
                success: $result['success'],
                bonusId: $result['bonus']['id'],
                amount: $result['bonus']['amount'],
                wageringMultiplier: $result['bonus']['wagering_required'] / $result['bonus']['amount'],
                wageringRequired: $result['bonus']['wagering_required'],
                expiresAt: null
            );
        } catch (\Exception $e) {
            return new ClaimBonusResponse(
                success: false,
                bonusId: '',
                amount: 0,
                wageringMultiplier: 0,
                wageringRequired: 0,
                error: $e->getMessage()
            );
        }
    }
}
