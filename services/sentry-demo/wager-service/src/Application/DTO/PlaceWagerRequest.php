<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class PlaceWagerRequest
{
    public function __construct(
        public array $validationData,
        public string $gameResult,
        public float $payout
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            validationData: $data['validationData'] ?? $data['validation_data'] ?? [],
            gameResult: $data['gameResult'] ?? $data['game_result'] ?? '',
            payout: (float)($data['payout'] ?? 0)
        );
    }
}
