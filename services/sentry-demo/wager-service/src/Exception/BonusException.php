<?php

namespace App\Exception;

use Symfony\Component\HttpKernel\Exception\HttpException;

class BonusException extends HttpException
{
    public const NO_ACTIVE_BONUS = 'NO_ACTIVE_BONUS';
    public const BONUS_ALREADY_ACTIVE = 'BONUS_ALREADY_ACTIVE';
    public const BONUS_EXPIRED = 'BONUS_EXPIRED';
    public const BONUS_NOT_FOUND = 'BONUS_NOT_FOUND';
    public const CONVERSION_FAILED = 'CONVERSION_FAILED';

    public function __construct(
        string $code,
        string $message,
        \Throwable $previous = null,
        array $headers = [],
        int $statusCode = 400
    ) {
        parent::__construct($statusCode, sprintf('[%s] %s', $code, $message), $previous, $headers);
    }

    public static function noActiveBonus(string $userId): self
    {
        return new self(
            self::NO_ACTIVE_BONUS,
            sprintf('User %s has no active bonus', $userId)
        );
    }

    public static function bonusAlreadyActive(string $userId): self
    {
        return new self(
            self::BONUS_ALREADY_ACTIVE,
            sprintf('User %s already has an active bonus', $userId)
        );
    }

    public static function bonusExpired(string $bonusId): self
    {
        return new self(
            self::BONUS_EXPIRED,
            sprintf('Bonus %s has expired', $bonusId)
        );
    }

    public static function bonusNotFound(string $bonusId): self
    {
        return new self(
            self::BONUS_NOT_FOUND,
            sprintf('Bonus %s not found', $bonusId),
            null,
            [],
            404
        );
    }

    public static function conversionFailed(string $reason): self
    {
        return new self(
            self::CONVERSION_FAILED,
            sprintf('Bonus conversion failed: %s', $reason),
            null,
            [],
            500
        );
    }
}