<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;

class HealthController extends AbstractController
{
    public function check(): JsonResponse
    {
        return $this->json([
            'status' => 'ok',
            'service' => 'wager-service',
            'timestamp' => time()
        ]);
    }
}
