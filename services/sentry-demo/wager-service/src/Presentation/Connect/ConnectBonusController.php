<?php

declare(strict_types=1);

namespace App\Presentation\Connect;

use App\Application\UseCase\Bonus\ClaimBonusUseCase;
use App\Application\UseCase\Bonus\GetBonusProgressUseCase;
use App\Application\UseCase\Bonus\ConvertBonusUseCase;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

// Generated protobuf classes from @gitops-poc-dzha/wager-service-php
use Wager\V1\ClaimRequest;
use Wager\V1\ClaimResponse;
use Wager\V1\GetProgressRequest;
use Wager\V1\GetProgressResponse;
use Wager\V1\ConvertRequest;
use Wager\V1\ConvertResponse;

/**
 * Connect Protocol Controller for BonusService
 *
 * Uses generated protobuf classes for type-safe JSON serialization.
 * Connect Protocol = HTTP POST + JSON (protobuf-compatible)
 */
class ConnectBonusController extends AbstractController
{
    public function __construct(
        private ClaimBonusUseCase $claimBonus,
        private GetBonusProgressUseCase $getProgress,
        private ConvertBonusUseCase $convertBonus
    ) {}

    #[Route('/wager.v1.BonusService/Claim', name: 'connect_bonus_claim', methods: ['POST'])]
    public function claim(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new ClaimRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            // Execute use case
            $result = $this->claimBonus->execute(
                \App\Application\DTO\ClaimBonusRequest::fromArray([
                    'userId' => $protoRequest->getUserId(),
                ]),
                $request
            );

            // Build response using generated protobuf class
            $protoResponse = new ClaimResponse();
            $protoResponse->setSuccess($result->success);
            $protoResponse->setBonusId($result->bonusId);
            $protoResponse->setAmount($result->amount);
            $protoResponse->setWageringMultiplier($result->wageringMultiplier);
            $protoResponse->setWageringRequired($result->wageringRequired);
            $protoResponse->setExpiresAt($result->expiresAt);
            if ($result->error) {
                $protoResponse->setError($result->error);
            }

            return new Response(
                $protoResponse->serializeToJsonString(),
                200,
                ['Content-Type' => 'application/json']
            );
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.BonusService/GetProgress', name: 'connect_bonus_progress', methods: ['POST'])]
    public function getProgress(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new GetProgressRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            // Execute use case
            $result = $this->getProgress->execute(
                \App\Application\DTO\GetProgressRequest::fromArray([
                    'userId' => $protoRequest->getUserId(),
                ])
            );

            // Build response using generated protobuf class
            $protoResponse = new GetProgressResponse();
            $protoResponse->setHasActiveBonus($result->hasActiveBonus);
            $protoResponse->setBonusBalance($result->bonusBalance);
            $protoResponse->setRealBalance($result->realBalance);
            $protoResponse->setProgressPercent($result->progressPercent);
            $protoResponse->setWageringRequired($result->wageringRequired);
            $protoResponse->setWageredAmount($result->wageredAmount);
            $protoResponse->setRemaining($result->remaining);
            $protoResponse->setCanConvert($result->canConvert);
            $protoResponse->setExpiresAt($result->expiresAt);

            return new Response(
                $protoResponse->serializeToJsonString(),
                200,
                ['Content-Type' => 'application/json']
            );
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.BonusService/Convert', name: 'connect_bonus_convert', methods: ['POST'])]
    public function convert(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new ConvertRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            // Execute use case
            $result = $this->convertBonus->execute(
                \App\Application\DTO\ConvertBonusRequest::fromArray([
                    'userId' => $protoRequest->getUserId(),
                ])
            );

            // Build response using generated protobuf class
            $protoResponse = new ConvertResponse();
            $protoResponse->setSuccess($result->success);
            $protoResponse->setConvertedAmount($result->convertedAmount);
            $protoResponse->setNewBalance($result->newBalance);
            if ($result->error) {
                $protoResponse->setError($result->error);
            }

            return new Response(
                $protoResponse->serializeToJsonString(),
                200,
                ['Content-Type' => 'application/json']
            );
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    private function connectError(\Exception $e): Response
    {
        \Sentry\captureException($e);

        // Connect protocol error format
        $errorResponse = [
            'code' => $this->mapExceptionToCode($e),
            'message' => $e->getMessage(),
        ];

        return new Response(
            json_encode($errorResponse),
            $this->getStatusCode($e),
            ['Content-Type' => 'application/json']
        );
    }

    private function mapExceptionToCode(\Exception $e): string
    {
        return match (true) {
            $e instanceof \App\Exception\BonusAlreadyClaimedException => 'already_exists',
            $e instanceof \App\Exception\BonusNotFoundException => 'not_found',
            $e instanceof \LogicException => 'failed_precondition',
            default => 'internal',
        };
    }

    private function getStatusCode(\Exception $e): int
    {
        $code = $e->getCode();
        return ($code >= 400 && $code < 600) ? $code : 500;
    }
}
