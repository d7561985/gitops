<?php

namespace App\Exception;

class BonusNotFoundException extends \Exception
{
    public function __construct(string $message = 'Bonus not found', int $code = 404, \Throwable $previous = null)
    {
        parent::__construct($message, $code, $previous);
    }
}