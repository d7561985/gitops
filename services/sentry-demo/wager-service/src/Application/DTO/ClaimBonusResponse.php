<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class ClaimBonusResponse
{
    public function __construct(
        public bool $success,
        public string $bonusId,
        public float $amount,
        public float $wageringMultiplier,
        public float $wageringRequired,
        public ?string $expiresAt = null,
        public ?string $error = null
    ) {}

    public function toArray(): array
    {
        return [
            'success' => $this->success,
            'bonusId' => $this->bonusId,
            'amount' => $this->amount,
            'wageringMultiplier' => $this->wageringMultiplier,
            'wageringRequired' => $this->wageringRequired,
            'expiresAt' => $this->expiresAt,
            'error' => $this->error,
        ];
    }
}
