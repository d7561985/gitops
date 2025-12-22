<?php

declare(strict_types=1);

namespace App\Application\UseCase\Wager;

use App\Application\DTO\GetHistoryRequest;
use App\Application\DTO\GetHistoryResponse;
use App\Service\WagerService;

/**
 * Get Wager History Use Case
 */
final class GetWagerHistoryUseCase
{
    public function __construct(
        private WagerService $wagerService
    ) {}

    public function execute(GetHistoryRequest $request): GetHistoryResponse
    {
        $result = $this->wagerService->getWagerHistory(
            $request->userId,
            $request->limit
        );

        // Transform to proto-compatible format
        $wagers = array_map(fn($w) => [
            'wagerId' => $w['wager_id'],
            'userId' => $result['user_id'],
            'gameId' => $w['game_id'],
            'amount' => $w['amount'],
            'gameResult' => $w['result'],
            'payout' => $w['payout'],
            'bonusUsed' => $w['bonus_used'],
            'realUsed' => $w['real_used'],
            'createdAt' => $w['timestamp'],
        ], $result['history']);

        return new GetHistoryResponse(
            wagers: $wagers,
            totalCount: $result['count']
        );
    }
}
