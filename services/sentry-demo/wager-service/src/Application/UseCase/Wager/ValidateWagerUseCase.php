<?php

declare(strict_types=1);

namespace App\Application\UseCase\Wager;

use App\Application\DTO\ValidateWagerRequest;
use App\Application\DTO\ValidateWagerResponse;
use App\Service\WagerService;

/**
 * Validate Wager Use Case
 * Wraps WagerService with clean DTOs for protocol-agnostic interface
 */
final class ValidateWagerUseCase
{
    public function __construct(
        private WagerService $wagerService
    ) {}

    public function execute(ValidateWagerRequest $request): ValidateWagerResponse
    {
        $result = $this->wagerService->validateWager(
            $request->userId,
            $request->amount,
            $request->gameId
        );

        return new ValidateWagerResponse(
            valid: $result['valid'],
            validationToken: $result['validation_token'] ?? bin2hex(random_bytes(16)),
            bonusUsed: $result['bonus_used'],
            realUsed: $result['real_used'],
            userId: $result['user_id'],
            amount: $result['amount'],
            gameId: $result['game_id'],
            balanceBefore: $result['balance_before'] ?? null
        );
    }
}
