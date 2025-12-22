<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class ValidateWagerResponse
{
    public function __construct(
        public bool $valid,
        public string $validationToken,
        public float $bonusUsed,
        public float $realUsed,
        public string $userId,
        public float $amount,
        public string $gameId,
        public ?array $balanceBefore = null
    ) {}

    public function toArray(): array
    {
        return [
            'valid' => $this->valid,
            'validationToken' => $this->validationToken,
            'bonusUsed' => $this->bonusUsed,
            'realUsed' => $this->realUsed,
            'userId' => $this->userId,
            'amount' => $this->amount,
            'gameId' => $this->gameId,
        ];
    }

    public function toSnakeCase(): array
    {
        return [
            'valid' => $this->valid,
            'validation_token' => $this->validationToken,
            'bonus_used' => $this->bonusUsed,
            'real_used' => $this->realUsed,
            'user_id' => $this->userId,
            'amount' => $this->amount,
            'game_id' => $this->gameId,
            'balance_before' => $this->balanceBefore,
        ];
    }
}
