<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class PlaceWagerResponse
{
    public function __construct(
        public bool $success,
        public string $wagerId,
        public ?WageringProgressDTO $wageringProgress = null
    ) {}

    public function toArray(): array
    {
        return [
            'success' => $this->success,
            'wagerId' => $this->wagerId,
            'wageringProgress' => $this->wageringProgress?->toArray(),
        ];
    }

    public function toSnakeCase(): array
    {
        return [
            'success' => $this->success,
            'wager_id' => $this->wagerId,
            'wagering_progress' => $this->wageringProgress?->toSnakeCase(),
        ];
    }
}
