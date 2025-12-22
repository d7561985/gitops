<?php

namespace App\Exception;

class ConcurrentWagerException extends \Exception
{
    public function __construct(string $message = 'Concurrent wager attempt detected', int $code = 409, \Throwable $previous = null)
    {
        parent::__construct($message, $code, $previous);
    }
}