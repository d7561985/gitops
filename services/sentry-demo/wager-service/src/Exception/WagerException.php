<?php

namespace App\Exception;

use Symfony\Component\HttpKernel\Exception\HttpException;

class WagerException extends HttpException
{
    public const INSUFFICIENT_BALANCE = 'INSUFFICIENT_BALANCE';
    public const INVALID_WAGER_AMOUNT = 'INVALID_WAGER_AMOUNT';
    public const CONCURRENT_WAGER = 'CONCURRENT_WAGER';
    public const WAGER_LIMIT_EXCEEDED = 'WAGER_LIMIT_EXCEEDED';
    public const GAME_NOT_AVAILABLE = 'GAME_NOT_AVAILABLE';

    public function __construct(
        string $code,
        string $message,
        \Throwable $previous = null,
        array $headers = [],
        int $statusCode = 400
    ) {
        parent::__construct($statusCode, sprintf('[%s] %s', $code, $message), $previous, $headers);
    }

    public static function insufficientBalance(float $required, float $available): self
    {
        return new self(
            self::INSUFFICIENT_BALANCE,
            sprintf('Insufficient balance. Required: %.2f, Available: %.2f', $required, $available)
        );
    }

    public static function invalidWagerAmount(float $amount): self
    {
        return new self(
            self::INVALID_WAGER_AMOUNT,
            sprintf('Invalid wager amount: %.2f. Must be positive', $amount)
        );
    }

    public static function concurrentWager(string $userId): self
    {
        return new self(
            self::CONCURRENT_WAGER,
            sprintf('Concurrent wager attempt detected for user %s', $userId),
            null,
            [],
            409
        );
    }

    public static function wagerLimitExceeded(float $limit): self
    {
        return new self(
            self::WAGER_LIMIT_EXCEEDED,
            sprintf('Wager amount exceeds limit of %.2f', $limit)
        );
    }

    public static function gameNotAvailable(string $gameId): self
    {
        return new self(
            self::GAME_NOT_AVAILABLE,
            sprintf('Game %s is not available', $gameId),
            null,
            [],
            503
        );
    }
}