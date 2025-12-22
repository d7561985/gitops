<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class WageringProgressDTO
{
    public function __construct(
        public float $progressPercent,
        public float $remaining,
        public bool $canConvert,
        public float $totalRequired = 0,
        public float $totalWagered = 0
    ) {}

    public function toArray(): array
    {
        return [
            'progressPercent' => $this->progressPercent,
            'remaining' => $this->remaining,
            'canConvert' => $this->canConvert,
            'totalRequired' => $this->totalRequired,
            'totalWagered' => $this->totalWagered,
        ];
    }

    public function toSnakeCase(): array
    {
        return [
            'progress' => $this->progressPercent,
            'remaining' => $this->remaining,
            'can_convert' => $this->canConvert,
            'total_required' => $this->totalRequired,
            'total_wagered' => $this->totalWagered,
        ];
    }
}
