<?php

namespace App\Service;

use App\Document\ActiveBonus;
use App\Document\BalanceSnapshot;
use App\Document\UserBonus;
use App\Document\WagerHistory;
use App\Exception\ConcurrentWagerException;
use App\Exception\InsufficientBalanceException;
use Doctrine\ODM\MongoDB\DocumentManager;
use Doctrine\ODM\MongoDB\LockException;
use Psr\Log\LoggerInterface;
use Sentry\Metrics\MetricsUnit;
use Sentry\SentrySdk;
use Sentry\Tracing\SpanContext;

class WagerService
{
    public function __construct(
        private DocumentManager $dm,
        private IntegrationService $integrationService,
        private LoggerInterface $logger
    ) {}
    
    public function validateWager(string $userId, float $amount, string $gameId): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('wager.validate');
            $context->setDescription('Validate wager attempt');
            
            $childSpan = $span->startChild($context);
            $childSpan->setData([
                'user_id' => $userId,
                'wager_amount' => $amount
            ]);
        }
        
        try {
            // Get user bonus with lock to prevent concurrent modifications
            $userBonus = $this->dm->getRepository(UserBonus::class)->find($userId);
            
            if (!$userBonus) {
                // Auto-create bonus for POC - every user gets 1000 starting balance + welcome bonus
                $userBonus = new UserBonus($userId);
                $userBonus->setRealBalance(1000.0);  // Starting balance for POC
                
                // Auto-create welcome bonus for POC
                $bonus = new ActiveBonus(1000.0, 2); // $1000 bonus with 2x wagering
                $userBonus->setActiveBonus($bonus);
                $userBonus->setBonusBalance(1000.0);
                $userBonus->incrementBonusesClaimed();
                
                $this->dm->persist($userBonus);
                $this->dm->flush();
                
                $this->logger->info('Auto-created user with welcome bonus for POC', [
                    'user_id' => $userId,
                    'real_balance' => 1000.0,
                    'bonus_balance' => 1000.0,
                    'bonus_id' => $bonus->getId(),
                    'wagering_required' => 2000.0
                ]);
            }
            
            // Check total balance
            if (!$userBonus->canWager($amount)) {
                throw new InsufficientBalanceException(
                    sprintf('Insufficient balance. Required: %.2f, Available: %.2f', 
                        $amount, 
                        $userBonus->getTotalBalance()
                    )
                );
            }
            
            // Calculate balance deduction
            $deduction = $userBonus->calculateBalanceDeduction($amount);
            
            if (!$deduction['sufficient']) {
                throw new InsufficientBalanceException(
                    sprintf('Insufficient real balance. Required: %.2f, Available: %.2f',
                        $deduction['real_used'],
                        $userBonus->getRealBalance()
                    )
                );
            }
            
            // Try to acquire lock
            $currentVersion = $userBonus->getVersion();
            
            try {
                // Atomic update with version check
                $result = $this->dm->createQueryBuilder(UserBonus::class)
                    ->updateOne()
                    ->field('_id')->equals($userId)
                    ->field('version')->equals($currentVersion)
                    ->field('version')->inc(1)
                    ->field('lastWagerTime')->set(new \DateTime())
                    ->getQuery()
                    ->execute();
                
                if (!$result || $result->getModifiedCount() === 0) {
                    throw new ConcurrentWagerException('Another wager is in progress');
                }
                
            } catch (\Exception $e) {
                if ($e instanceof ConcurrentWagerException) {
                    throw $e;
                }
                throw new \RuntimeException('Failed to lock user for wager', 0, $e);
            }
            
            // Track validation metric
            // SentrySdk::getCurrentHub()->getMetrics()->emit(
            //     'counter',
            //     'wager.validated',
            //     1,
            //     MetricsUnit::none(),
            //     ['result' => 'success']
            // );
            
            return [
                'valid' => true,
                'user_id' => $userId,
                'amount' => $amount,
                'game_id' => $gameId,
                'bonus_used' => $deduction['bonus_used'],
                'real_used' => $deduction['real_used'],
                'balance_before' => [
                    'real' => $userBonus->getRealBalance(),
                    'bonus' => $userBonus->getBonusBalance(),
                    'total' => $userBonus->getTotalBalance()
                ]
            ];
            
        } catch (InsufficientBalanceException $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::invalidArgument());
            
            // SentrySdk::getCurrentHub()->getMetrics()->emit(
            //     'counter',
            //     'wager.validated',
            //     1,
            //     MetricsUnit::none(),
            //     ['result' => 'insufficient_balance']
            // );
            
            throw $e;
        } catch (\Exception $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::internalError());
            throw $e;
        } finally {
            $childSpan?->finish();
        }
    }
    
    public function placeWager(array $validationData, string $gameResult, float $payout = 0): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('wager.place');
            $context->setDescription('Place wager and update balances');
            
            $childSpan = $span->startChild($context);
        }
        
        $startTime = microtime(true);
        
        try {
            $userId = $validationData['user_id'];
            $amount = $validationData['amount'];
            $gameId = $validationData['game_id'];
            $bonusUsed = $validationData['bonus_used'] ?? 0.0;
            $realUsed = $validationData['real_used'] ?? $amount;
            
            // Get user bonus record
            $userBonus = $this->dm->getRepository(UserBonus::class)->find($userId);
            
            if (!$userBonus) {
                // This should not happen as user should be created during validation
                // But just in case, create with same pattern
                $userBonus = new UserBonus($userId);
                $userBonus->setRealBalance(1000.0);
                
                $bonus = new ActiveBonus(1000.0, 2);
                $userBonus->setActiveBonus($bonus);
                $userBonus->setBonusBalance(1000.0);
                $userBonus->incrementBonusesClaimed();
                
                $this->dm->persist($userBonus);
                $this->dm->flush();
                
                $this->logger->warning('Had to auto-create user bonus in placeWager - should have been created in validate', [
                    'user_id' => $userId
                ]);
            }
            
            // Record initial state
            $balanceBefore = $validationData['balance_before'];
            $activeBonus = $userBonus->getActiveBonus();
            $wageringProgressBefore = $activeBonus ? $activeBonus->getWageringCompleted() : 0;
            
            // Create wager history record
            $wagerHistory = new WagerHistory($userId, $gameId, $amount);
            $wagerHistory->setBonusUsed($bonusUsed);
            $wagerHistory->setRealUsed($realUsed);
            $wagerHistory->setGameResult($gameResult);
            $wagerHistory->setPayout($payout);
            
            if ($activeBonus) {
                $wagerHistory->setBonusId($activeBonus->getId());
                $wagerHistory->setWageringProgressBefore($wageringProgressBefore);
            }
            
            // Get current span info for tracing
            $currentSpan = SentrySdk::getCurrentHub()->getSpan();
            if ($currentSpan) {
                $wagerHistory->setTraceId($currentSpan->getTraceId());
                $wagerHistory->setSpanId($currentSpan->getSpanId());
            }
            
            // Update balances
            $userBonus->setBonusBalance($userBonus->getBonusBalance() - $bonusUsed);
            $userBonus->setRealBalance($userBonus->getRealBalance() - $realUsed + $payout);
            $userBonus->addToLifetimeWagered($amount);
            
            // Update wagering progress if there's an active bonus
            // For POC: any wager counts towards wagering requirement
            if ($activeBonus) {
                $activeBonus->addWageringProgress($amount);
                $wagerHistory->setWageringProgressAfter($activeBonus->getWageringCompleted());
                
                $this->logger->info('Updated wagering progress', [
                    'user_id' => $userId,
                    'bonus_id' => $activeBonus->getId(),
                    'amount_wagered' => $amount,
                    'progress_before' => $wageringProgressBefore,
                    'progress_after' => $activeBonus->getWageringCompleted()
                ]);
            }
            
            // Set balance snapshot
            $balanceSnapshot = new BalanceSnapshot(
                $balanceBefore['real'],
                $userBonus->getRealBalance(),
                $balanceBefore['bonus'],
                $userBonus->getBonusBalance()
            );
            $wagerHistory->setBalanceSnapshot($balanceSnapshot);
            
            // Set processing time
            $processingTime = (int)((microtime(true) - $startTime) * 1000);
            $wagerHistory->setProcessingTimeMs($processingTime);
            
            // Persist changes
            $this->dm->persist($wagerHistory);
            $this->dm->persist($userBonus);
            $this->dm->flush();
                
                // Track wager metrics
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'distribution',
                //     'wager.amount',
                //     $amount,
                //     MetricsUnit::none(),
                //     ['currency' => 'USD']
                // );
                
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'counter',
                //     'wager.placed',
                //     1,
                //     MetricsUnit::none(),
                //     ['result' => $gameResult]
                // );
                
                // Track wagering velocity
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'gauge',
                //     'wager.processing_time',
                //     $processingTime,
                //     MetricsUnit::millisecond(),
                //     []
                // );
                
                // Add breadcrumb
                \Sentry\addBreadcrumb(
                    'wager.placed',
                    'Wager placed successfully',
                    [
                        'user_id' => $userId,
                        'wager_id' => $wagerHistory->getWagerId(),
                        'amount' => $amount,
                        'result' => $gameResult,
                        'payout' => $payout
                    ]
                );
                
                $this->logger->info('Wager placed', [
                    'user_id' => $userId,
                    'wager_id' => $wagerHistory->getWagerId(),
                    'amount' => $amount,
                    'result' => $gameResult,
                    'bonus_progress' => $activeBonus ? $activeBonus->getProgressPercentage() : null
                ]);
                
                // Check if bonus is complete
                $bonusComplete = false;
                if ($activeBonus && $activeBonus->isComplete()) {
                    $bonusComplete = true;
                    
                    // Notify that bonus is ready for conversion
                    // SentrySdk::getCurrentHub()->getMetrics()->emit(
                    //     'counter',
                    //     'bonus.ready_for_conversion',
                    //     1,
                    //     MetricsUnit::none(),
                    //     ['bonus_type' => $activeBonus->getType()]
                    // );
                }
                
                return [
                    'success' => true,
                    'wager_id' => $wagerHistory->getWagerId(),
                    'balance_after' => [
                        'real' => $userBonus->getRealBalance(),
                        'bonus' => $userBonus->getBonusBalance(),
                        'total' => $userBonus->getTotalBalance()
                    ],
                    'wagering_progress' => $activeBonus ? [
                        'completed' => $activeBonus->getWageringCompleted(),
                        'required' => $activeBonus->getWageringRequired(),
                        'percentage' => $activeBonus->getProgressPercentage(),
                        'is_complete' => $bonusComplete
                    ] : null,
                    'processing_time_ms' => $processingTime
                ];
            
        } catch (\Exception $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::internalError());
            throw $e;
        } finally {
            $childSpan?->finish();
        }
    }
    
    public function getWagerHistory(string $userId, int $limit = 10): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('wager.history');
            $context->setDescription('Get wager history');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            $qb = $this->dm->createQueryBuilder(WagerHistory::class);
            $qb->field('userId')->equals($userId)
               ->sort('timestamp', -1)
               ->limit($limit);
            
            $wagers = $qb->getQuery()->execute();
            
            $history = [];
            foreach ($wagers as $wager) {
                $history[] = [
                    'wager_id' => $wager->getWagerId(),
                    'game_id' => $wager->getGameId(),
                    'amount' => $wager->getWagerAmount(),
                    'bonus_used' => $wager->getBonusUsed(),
                    'real_used' => $wager->getRealUsed(),
                    'result' => $wager->getGameResult(),
                    'payout' => $wager->getPayout(),
                    'timestamp' => $wager->getTimestamp()->format('c'),
                    'balance_after' => [
                        'real' => $wager->getBalanceSnapshot()->getRealAfter(),
                        'bonus' => $wager->getBalanceSnapshot()->getBonusAfter(),
                        'total' => $wager->getBalanceSnapshot()->getTotalAfter()
                    ]
                ];
            }
            
            return [
                'user_id' => $userId,
                'history' => $history,
                'count' => count($history)
            ];
            
        } finally {
            $childSpan?->finish();
        }
    }
    
    /**
     * Demo method to trigger various wager-related errors
     */
    public function triggerDemoError(string $errorType): void
    {
        switch ($errorType) {
            case 'insufficient_balance':
                throw new InsufficientBalanceException('[DEMO] Insufficient balance: Required 50.00, Available 10.00');
                
            case 'concurrent_wager':
                throw new ConcurrentWagerException('[DEMO] Another wager is already in progress');
                
            case 'database_error':
                throw new \MongoException('[DEMO] MongoDB connection timeout');
                
            case 'invalid_amount':
                throw new \InvalidArgumentException('[DEMO] Invalid wager amount: -50.00');
                
            default:
                throw new \InvalidArgumentException("[DEMO] Unknown error type: $errorType");
        }
    }
}