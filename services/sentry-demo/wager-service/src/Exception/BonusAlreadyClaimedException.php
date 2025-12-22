<?php

namespace App\Exception;

class BonusAlreadyClaimedException extends \Exception
{
    public function __construct(string $message = 'Bonus already claimed', int $code = 409, \Throwable $previous = null)
    {
        parent::__construct($message, $code, $previous);
    }
}