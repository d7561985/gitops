<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class GetHistoryResponse
{
    public function __construct(
        public array $wagers,
        public int $totalCount
    ) {}

    public function toArray(): array
    {
        return [
            'wagers' => $this->wagers,
            'totalCount' => $this->totalCount,
        ];
    }

    public function toSnakeCase(): array
    {
        return [
            'history' => $this->wagers,
            'count' => $this->totalCount,
        ];
    }
}
