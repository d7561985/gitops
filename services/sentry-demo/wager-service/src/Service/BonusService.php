<?php

namespace App\Service;

use App\Document\ActiveBonus;
use App\Document\BonusConversion;
use App\Document\UserBonus;
use App\Document\WagerHistory;
use App\Exception\BonusAlreadyClaimedException;
use App\Exception\BonusNotFoundException;
use App\Exception\InsufficientBalanceException;
use Doctrine\ODM\MongoDB\DocumentManager;
use Psr\Log\LoggerInterface;
use Sentry\Metrics\MetricsUnit;
use Sentry\SentrySdk;
use Sentry\Tracing\SpanContext;
use Symfony\Component\HttpFoundation\Request;

class BonusService
{
    private const WELCOME_BONUS_AMOUNT = 1000.0;
    private const WAGERING_MULTIPLIER = 2.0;
    
    public function __construct(
        private DocumentManager $dm,
        private LoggerInterface $logger
    ) {}
    
    public function claimWelcomeBonus(string $userId, Request $request): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('bonus.claim');
            $context->setDescription('Claim welcome bonus');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            // Check if user already has bonuses
            $userBonus = $this->dm->getRepository(UserBonus::class)->find($userId);
            
            if ($userBonus && $userBonus->getActiveBonus()) {
                throw new BonusAlreadyClaimedException('User already has an active bonus');
            }
            
            // Create new user bonus record if doesn't exist
            if (!$userBonus) {
                $userBonus = new UserBonus($userId);
            }
            
            // Create welcome bonus
            $bonus = new ActiveBonus(self::WELCOME_BONUS_AMOUNT, self::WAGERING_MULTIPLIER);
            $userBonus->setActiveBonus($bonus);
            $userBonus->setBonusBalance($userBonus->getBonusBalance() + self::WELCOME_BONUS_AMOUNT);
            $userBonus->incrementBonusesClaimed();
            
            // Persist changes
            $this->dm->persist($userBonus);
            $this->dm->flush();
            
            // Track business metric
            // SentrySdk::getCurrentHub()->getMetrics()->emit(
            //     'distribution',
            //     'bonus.claimed',
            //     self::WELCOME_BONUS_AMOUNT,
            //     MetricsUnit::none(),
            //     ['bonus_type' => 'welcome']
            // );
            
            // Add breadcrumb
            \Sentry\addBreadcrumb(
                'bonus.claimed',
                'Claimed welcome bonus',
                [
                    'user_id' => $userId,
                    'amount' => self::WELCOME_BONUS_AMOUNT,
                    'wagering_required' => self::WELCOME_BONUS_AMOUNT * self::WAGERING_MULTIPLIER
                ]
            );
            
            $this->logger->info('Welcome bonus claimed', [
                'user_id' => $userId,
                'bonus_id' => $bonus->getId(),
                'amount' => self::WELCOME_BONUS_AMOUNT
            ]);
            
            return [
                'success' => true,
                'bonus' => [
                    'id' => $bonus->getId(),
                    'type' => $bonus->getType(),
                    'amount' => $bonus->getAmount(),
                    'wagering_required' => $bonus->getWageringRequired(),
                    'wagering_completed' => 0,
                    'progress_percentage' => 0
                ],
                'balance' => [
                    'real' => $userBonus->getRealBalance(),
                    'bonus' => $userBonus->getBonusBalance(),
                    'total' => $userBonus->getTotalBalance()
                ]
            ];
            
        } catch (\Exception $e) {
            $childSpan?->setStatus(\Sentry\Tracing\SpanStatus::internalError());
            throw $e;
        } finally {
            $childSpan?->finish();
        }
    }
    
    public function getProgress(string $userId): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('bonus.get_progress');
            $context->setDescription('Get wagering progress');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            $userBonus = $this->dm->getRepository(UserBonus::class)->find($userId);
            
            if (!$userBonus) {
                // Auto-create bonus for POC - every user gets 1000 starting balance + welcome bonus
                $userBonus = new UserBonus($userId);
                $userBonus->setRealBalance(1000.0);  // Starting balance for POC
                
                // Auto-create welcome bonus for POC
                $bonus = new ActiveBonus(self::WELCOME_BONUS_AMOUNT, self::WAGERING_MULTIPLIER);
                $userBonus->setActiveBonus($bonus);
                $userBonus->setBonusBalance(self::WELCOME_BONUS_AMOUNT);
                $userBonus->incrementBonusesClaimed();
                
                $this->dm->persist($userBonus);
                $this->dm->flush();
                
                $this->logger->info('Auto-created user with welcome bonus for POC', [
                    'user_id' => $userId,
                    'real_balance' => 1000.0,
                    'bonus_balance' => self::WELCOME_BONUS_AMOUNT,
                    'bonus_id' => $bonus->getId()
                ]);
            }
            
            $activeBonus = $userBonus->getActiveBonus();
            
            if (!$activeBonus) {
                return [
                    'has_active_bonus' => false,
                    'balance' => [
                        'real' => $userBonus->getRealBalance(),
                        'bonus' => 0,
                        'total' => $userBonus->getRealBalance()
                    ]
                ];
            }
            
            // Track progress metric
            if ($activeBonus->getWageringRequired() > 0) {
                $progressRatio = $activeBonus->getWageringCompleted() / $activeBonus->getWageringRequired();
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'gauge',
                //     'bonus.progress',
                //     $progressRatio,
                //     MetricsUnit::ratio(),
                //     ['user_id' => $userId]
                // );
            }
            
            return [
                'has_active_bonus' => true,
                'bonus' => [
                    'id' => $activeBonus->getId(),
                    'type' => $activeBonus->getType(),
                    'amount' => $activeBonus->getAmount(),
                    'wagering_required' => $activeBonus->getWageringRequired(),
                    'wagering_completed' => $activeBonus->getWageringCompleted(),
                    'progress_percentage' => $activeBonus->getProgressPercentage(),
                    'status' => $activeBonus->getStatus(),
                    'created_at' => $activeBonus->getCreatedAt()->format('c')
                ],
                'balance' => [
                    'real' => $userBonus->getRealBalance(),
                    'bonus' => $userBonus->getBonusBalance(),
                    'total' => $userBonus->getTotalBalance()
                ]
            ];
            
        } finally {
            $childSpan?->finish();
        }
    }
    
    public function convertBonusToReal(string $userId): array
    {
        $span = SentrySdk::getCurrentHub()->getSpan();
        $childSpan = null;
        
        if ($span) {
            $context = new SpanContext();
            $context->setOp('bonus.convert');
            $context->setDescription('Convert bonus to real money');
            
            $childSpan = $span->startChild($context);
        }
        
        try {
            $userBonus = $this->dm->getRepository(UserBonus::class)->find($userId);
            
            if (!$userBonus || !$userBonus->getActiveBonus()) {
                throw new BonusNotFoundException('No active bonus to convert');
            }
            
            $activeBonus = $userBonus->getActiveBonus();
            
            if (!$activeBonus->isComplete()) {
                throw new \LogicException('Bonus wagering requirements not met');
            }
            
            // Convert bonus to real balance
            $bonusAmount = $activeBonus->getAmount();
            $userBonus->setRealBalance($userBonus->getRealBalance() + $bonusAmount);
            $userBonus->setBonusBalance(0);
            $userBonus->setActiveBonus(null);
            $userBonus->incrementBonusesCompleted();
            
            // Create conversion record
            $conversion = new BonusConversion(
                $userId,
                $activeBonus->getId(),
                $bonusAmount,
                $activeBonus->getWageringCompleted(),
                $activeBonus->getCreatedAt()
            );
            
            // Calculate stats from wager history
            $wagerStats = $this->calculateWagerStats($userId, $activeBonus->getId());
            $conversion->setTotalWagers($wagerStats['total']);
            $conversion->setWinningWagers($wagerStats['wins']);
            
            $this->dm->persist($conversion);
            $this->dm->persist($userBonus);
            $this->dm->flush();
                
                // Track conversion metric
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'counter',
                //     'bonus.converted',
                //     1,
                //     MetricsUnit::none(),
                //     ['bonus_type' => 'welcome']
                // );
                
                // Track conversion time
                // SentrySdk::getCurrentHub()->getMetrics()->emit(
                //     'distribution',
                //     'bonus.conversion_time',
                //     $conversion->getDurationMinutes(),
                //     MetricsUnit::minute(),
                //     ['bonus_type' => 'welcome']
                // );
                
                $this->logger->info('Bonus converted to real money', [
                    'user_id' => $userId,
                    'bonus_id' => $activeBonus->getId(),
                    'amount' => $bonusAmount,
                    'duration_minutes' => $conversion->getDurationMinutes()
                ]);
                
            return [
                'success' => true,
                'converted_amount' => $bonusAmount,
                'new_balance' => [
                    'real' => $userBonus->getRealBalance(),
                    'bonus' => 0,
                    'total' => $userBonus->getRealBalance()
                ],
                'conversion' => [
                    'duration_minutes' => $conversion->getDurationMinutes(),
                    'total_wagered' => $conversion->getTotalWagered(),
                    'win_rate' => $conversion->getWinRate()
                ]
            ];
            
        } finally {
            $childSpan?->finish();
        }
    }
    
    private function calculateWagerStats(string $userId, string $bonusId): array
    {
        $qb = $this->dm->createQueryBuilder(WagerHistory::class);
        $qb->field('userId')->equals($userId)
           ->field('bonusId')->equals($bonusId);
        
        $wagers = $qb->getQuery()->execute();
        
        $total = 0;
        $wins = 0;
        
        foreach ($wagers as $wager) {
            $total++;
            if ($wager->getGameResult() === 'win') {
                $wins++;
            }
        }
        
        return ['total' => $total, 'wins' => $wins];
    }
    
    /**
     * Demo method to trigger various bonus-related errors
     */
    public function triggerDemoError(string $errorType): void
    {
        switch ($errorType) {
            case 'already_claimed':
                throw new BonusAlreadyClaimedException('[DEMO] User already claimed welcome bonus');
                
            case 'not_found':
                throw new BonusNotFoundException('[DEMO] No bonus found for user');
                
            case 'requirements_not_met':
                throw new \LogicException('[DEMO] Wagering requirements not met: 500/2000 completed');
                
            case 'conversion_failed':
                throw new \RuntimeException('[DEMO] Bonus conversion failed due to database error');
                
            default:
                throw new \InvalidArgumentException("[DEMO] Unknown error type: $errorType");
        }
    }
}