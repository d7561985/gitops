<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class GetProgressResponse
{
    public function __construct(
        public bool $hasActiveBonus,
        public float $bonusBalance,
        public float $realBalance,
        public float $progressPercent,
        public float $wageringRequired,
        public float $wageredAmount,
        public float $remaining,
        public bool $canConvert,
        public ?string $expiresAt = null
    ) {}

    public function toArray(): array
    {
        return [
            'hasActiveBonus' => $this->hasActiveBonus,
            'bonusBalance' => $this->bonusBalance,
            'realBalance' => $this->realBalance,
            'progressPercent' => $this->progressPercent,
            'wageringRequired' => $this->wageringRequired,
            'wageredAmount' => $this->wageredAmount,
            'remaining' => $this->remaining,
            'canConvert' => $this->canConvert,
            'expiresAt' => $this->expiresAt,
        ];
    }
}
