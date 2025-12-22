<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class ValidateWagerRequest
{
    public function __construct(
        public string $userId,
        public float $amount,
        public string $gameId
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            userId: $data['userId'] ?? $data['user_id'] ?? '',
            amount: (float)($data['amount'] ?? 0),
            gameId: $data['gameId'] ?? $data['game_id'] ?? ''
        );
    }
}
