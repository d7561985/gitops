<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class ConvertBonusResponse
{
    public function __construct(
        public bool $success,
        public float $convertedAmount,
        public float $newBalance,
        public ?string $error = null
    ) {}

    public function toArray(): array
    {
        return [
            'success' => $this->success,
            'convertedAmount' => $this->convertedAmount,
            'newBalance' => $this->newBalance,
            'error' => $this->error,
        ];
    }
}
