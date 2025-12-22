<?php

declare(strict_types=1);

namespace App\Presentation\Connect;

use App\Application\UseCase\Wager\ValidateWagerUseCase;
use App\Application\UseCase\Wager\PlaceWagerUseCase;
use App\Application\UseCase\Wager\GetWagerHistoryUseCase;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

// Generated protobuf classes from @gitops-poc-dzha/wager-service-php
use Wager\V1\ValidateRequest;
use Wager\V1\ValidateResponse;
use Wager\V1\PlaceRequest;
use Wager\V1\PlaceResponse;
use Wager\V1\GetHistoryRequest;
use Wager\V1\GetHistoryResponse;
use Wager\V1\WageringProgress;
use Wager\V1\Wager;

/**
 * Connect Protocol Controller for WagerService
 *
 * Uses generated protobuf classes for type-safe JSON serialization.
 * Connect Protocol = HTTP POST + JSON (protobuf-compatible)
 */
class ConnectWagerController extends AbstractController
{
    public function __construct(
        private ValidateWagerUseCase $validateWager,
        private PlaceWagerUseCase $placeWager,
        private GetWagerHistoryUseCase $getHistory
    ) {}

    #[Route('/wager.v1.WagerService/Validate', name: 'connect_wager_validate', methods: ['POST'])]
    public function validate(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new ValidateRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            // Execute use case
            $result = $this->validateWager->execute(
                \App\Application\DTO\ValidateWagerRequest::fromArray([
                    'userId' => $protoRequest->getUserId(),
                    'amount' => $protoRequest->getAmount(),
                    'gameId' => $protoRequest->getGameId(),
                ])
            );

            // Build response using generated protobuf class
            $protoResponse = new ValidateResponse();
            $protoResponse->setValid($result->valid);
            $protoResponse->setValidationToken($result->validationToken);
            $protoResponse->setBonusUsed($result->bonusUsed);
            $protoResponse->setRealUsed($result->realUsed);
            $protoResponse->setUserId($result->userId);
            $protoResponse->setAmount($result->amount);
            $protoResponse->setGameId($result->gameId);

            return new Response(
                $protoResponse->serializeToJsonString(),
                200,
                ['Content-Type' => 'application/json']
            );
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.WagerService/Place', name: 'connect_wager_place', methods: ['POST'])]
    public function place(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new PlaceRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            $validationData = $protoRequest->getValidationData();

            // Execute use case
            $result = $this->placeWager->execute(
                \App\Application\DTO\PlaceWagerRequest::fromArray([
                    'validationData' => [
                        'userId' => $validationData?->getUserId() ?? '',
                        'amount' => $validationData?->getAmount() ?? 0,
                        'gameId' => $validationData?->getGameId() ?? '',
                        'bonusUsed' => $validationData?->getBonusUsed() ?? 0,
                        'realUsed' => $validationData?->getRealUsed() ?? 0,
                        'validationToken' => $validationData?->getValidationToken() ?? '',
                    ],
                    'gameResult' => $protoRequest->getGameResult(),
                    'payout' => $protoRequest->getPayout(),
                ])
            );

            // Build response using generated protobuf class
            $protoResponse = new PlaceResponse();
            $protoResponse->setWagerId($result->wagerId);
            $protoResponse->setSuccess($result->success);

            if ($result->wageringProgress) {
                $progress = new WageringProgress();
                $progress->setProgressPercent($result->wageringProgress->progressPercent);
                $progress->setRemaining($result->wageringProgress->remaining);
                $progress->setCanConvert($result->wageringProgress->canConvert);
                $progress->setTotalRequired($result->wageringProgress->totalRequired);
                $progress->setTotalWagered($result->wageringProgress->totalWagered);
                $protoResponse->setWageringProgress($progress);
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

    #[Route('/wager.v1.WagerService/GetHistory', name: 'connect_wager_history', methods: ['POST'])]
    public function getHistory(Request $request): Response
    {
        try {
            // Parse request using generated protobuf class
            $protoRequest = new GetHistoryRequest();
            $protoRequest->mergeFromJsonString($request->getContent());

            // Execute use case
            $result = $this->getHistory->execute(
                \App\Application\DTO\GetHistoryRequest::fromArray([
                    'userId' => $protoRequest->getUserId(),
                    'limit' => $protoRequest->getLimit(),
                ])
            );

            // Build response using generated protobuf class
            $protoResponse = new GetHistoryResponse();
            $protoResponse->setTotalCount($result->totalCount);

            foreach ($result->wagers as $wagerData) {
                $wager = new Wager();
                $wager->setWagerId($wagerData->wagerId);
                $wager->setUserId($wagerData->userId);
                $wager->setGameId($wagerData->gameId);
                $wager->setAmount($wagerData->amount);
                $wager->setGameResult($wagerData->gameResult);
                $wager->setPayout($wagerData->payout);
                $wager->setBonusUsed($wagerData->bonusUsed);
                $wager->setRealUsed($wagerData->realUsed);
                $wager->setCreatedAt($wagerData->createdAt);
                $protoResponse->getWagers()[] = $wager;
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
            $e instanceof \InvalidArgumentException => 'invalid_argument',
            $e instanceof \App\Exception\InsufficientBalanceException => 'failed_precondition',
            $e instanceof \App\Exception\ConcurrentWagerException => 'aborted',
            default => 'internal',
        };
    }

    private function getStatusCode(\Exception $e): int
    {
        $code = $e->getCode();
        return ($code >= 400 && $code < 600) ? $code : 500;
    }
}
