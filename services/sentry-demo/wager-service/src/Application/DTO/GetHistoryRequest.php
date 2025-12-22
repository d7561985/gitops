<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class GetHistoryRequest
{
    public function __construct(
        public string $userId,
        public int $limit = 10
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            userId: $data['userId'] ?? $data['user_id'] ?? '',
            limit: min(100, max(1, (int)($data['limit'] ?? 10)))
        );
    }
}
