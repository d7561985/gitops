<?php

declare(strict_types=1);

namespace App\Application\DTO;

final readonly class ConvertBonusRequest
{
    public function __construct(
        public string $userId
    ) {}

    public static function fromArray(array $data): self
    {
        return new self(
            userId: $data['userId'] ?? $data['user_id'] ?? ''
        );
    }
}
