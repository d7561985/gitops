<?php

namespace App\Exception;

class InsufficientBalanceException extends \Exception
{
    public function __construct(string $message = 'Insufficient balance', int $code = 400, \Throwable $previous = null)
    {
        parent::__construct($message, $code, $previous);
    }
}