<?php

declare(strict_types=1);

namespace App\Application\UseCase\Bonus;

use App\Application\DTO\ConvertBonusRequest;
use App\Application\DTO\ConvertBonusResponse;
use App\Service\BonusService;

/**
 * Convert Bonus to Real Money Use Case
 */
final class ConvertBonusUseCase
{
    public function __construct(
        private BonusService $bonusService
    ) {}

    public function execute(ConvertBonusRequest $request): ConvertBonusResponse
    {
        try {
            $result = $this->bonusService->convertBonusToReal($request->userId);

            return new ConvertBonusResponse(
                success: $result['success'],
                convertedAmount: $result['converted_amount'],
                newBalance: $result['new_balance']['real']
            );
        } catch (\Exception $e) {
            return new ConvertBonusResponse(
                success: false,
                convertedAmount: 0,
                newBalance: 0,
                error: $e->getMessage()
            );
        }
    }
}
