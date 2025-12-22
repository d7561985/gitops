<?php

namespace App\Document;

use Doctrine\ODM\MongoDB\Mapping\Annotations as ODM;
use Doctrine\ODM\MongoDB\Types\Type;

#[ODM\Document(collection: "wager_history")]
#[ODM\Index(keys: ["userId" => 1, "timestamp" => -1])]
#[ODM\Index(keys: ["bonusId" => 1])]
#[ODM\Index(keys: ["traceId" => 1])]
class WagerHistory
{
    #[ODM\Id]
    private ?string $id = null;
    
    #[ODM\Field(type: Type::STRING)]
    private string $userId;
    
    #[ODM\Field(type: Type::STRING)]
    private string $wagerId;
    
    #[ODM\Field(type: Type::STRING)]
    private string $gameId;
    
    #[ODM\Field(type: Type::STRING)]
    private string $gameResult; // win, lose
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $wagerAmount;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $bonusUsed = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $realUsed = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $payout = 0.0;
    
    #[ODM\Field(type: Type::STRING, nullable: true)]
    private ?string $bonusId = null;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $wageringProgressBefore = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $wageringProgressAfter = 0.0;
    
    #[ODM\EmbedOne(targetDocument: BalanceSnapshot::class)]
    private BalanceSnapshot $balanceSnapshot;
    
    #[ODM\Field(type: Type::DATE)]
    private \DateTimeInterface $timestamp;
    
    #[ODM\Field(type: Type::INT)]
    private int $processingTimeMs = 0;
    
    #[ODM\Field(type: Type::STRING, nullable: true)]
    private ?string $traceId = null;
    
    #[ODM\Field(type: Type::STRING, nullable: true)]
    private ?string $spanId = null;
    
    public function __construct(string $userId, string $gameId, float $wagerAmount)
    {
        $this->userId = $userId;
        $this->gameId = $gameId;
        $this->wagerAmount = $wagerAmount;
        $this->wagerId = 'wager-' . date('Y-m-d-His') . '-' . bin2hex(random_bytes(4));
        $this->timestamp = new \DateTime();
        $this->gameResult = 'pending';
    }
    
    public function getId(): ?string
    {
        return $this->id;
    }
    
    public function getUserId(): string
    {
        return $this->userId;
    }
    
    public function getWagerId(): string
    {
        return $this->wagerId;
    }
    
    public function getGameId(): string
    {
        return $this->gameId;
    }
    
    public function getGameResult(): string
    {
        return $this->gameResult;
    }
    
    public function setGameResult(string $gameResult): self
    {
        $this->gameResult = $gameResult;
        return $this;
    }
    
    public function getWagerAmount(): float
    {
        return $this->wagerAmount;
    }
    
    public function getBonusUsed(): float
    {
        return $this->bonusUsed;
    }
    
    public function setBonusUsed(float $bonusUsed): self
    {
        $this->bonusUsed = $bonusUsed;
        return $this;
    }
    
    public function getRealUsed(): float
    {
        return $this->realUsed;
    }
    
    public function setRealUsed(float $realUsed): self
    {
        $this->realUsed = $realUsed;
        return $this;
    }
    
    public function getPayout(): float
    {
        return $this->payout;
    }
    
    public function setPayout(float $payout): self
    {
        $this->payout = $payout;
        return $this;
    }
    
    public function getBonusId(): ?string
    {
        return $this->bonusId;
    }
    
    public function setBonusId(?string $bonusId): self
    {
        $this->bonusId = $bonusId;
        return $this;
    }
    
    public function getWageringProgressBefore(): float
    {
        return $this->wageringProgressBefore;
    }
    
    public function setWageringProgressBefore(float $wageringProgressBefore): self
    {
        $this->wageringProgressBefore = $wageringProgressBefore;
        return $this;
    }
    
    public function getWageringProgressAfter(): float
    {
        return $this->wageringProgressAfter;
    }
    
    public function setWageringProgressAfter(float $wageringProgressAfter): self
    {
        $this->wageringProgressAfter = $wageringProgressAfter;
        return $this;
    }
    
    public function getBalanceSnapshot(): BalanceSnapshot
    {
        return $this->balanceSnapshot;
    }
    
    public function setBalanceSnapshot(BalanceSnapshot $balanceSnapshot): self
    {
        $this->balanceSnapshot = $balanceSnapshot;
        return $this;
    }
    
    public function getTimestamp(): \DateTimeInterface
    {
        return $this->timestamp;
    }
    
    public function getProcessingTimeMs(): int
    {
        return $this->processingTimeMs;
    }
    
    public function setProcessingTimeMs(int $processingTimeMs): self
    {
        $this->processingTimeMs = $processingTimeMs;
        return $this;
    }
    
    public function getTraceId(): ?string
    {
        return $this->traceId;
    }
    
    public function setTraceId(?string $traceId): self
    {
        $this->traceId = $traceId;
        return $this;
    }
    
    public function getSpanId(): ?string
    {
        return $this->spanId;
    }
    
    public function setSpanId(?string $spanId): self
    {
        $this->spanId = $spanId;
        return $this;
    }
}

#[ODM\EmbeddedDocument]
class BalanceSnapshot
{
    #[ODM\Field(type: Type::FLOAT)]
    private float $realBefore;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $realAfter;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $bonusBefore;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $bonusAfter;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $totalBefore;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $totalAfter;
    
    public function __construct(
        float $realBefore,
        float $realAfter,
        float $bonusBefore,
        float $bonusAfter
    ) {
        $this->realBefore = $realBefore;
        $this->realAfter = $realAfter;
        $this->bonusBefore = $bonusBefore;
        $this->bonusAfter = $bonusAfter;
        $this->totalBefore = $realBefore + $bonusBefore;
        $this->totalAfter = $realAfter + $bonusAfter;
    }
    
    public function getRealBefore(): float
    {
        return $this->realBefore;
    }
    
    public function getRealAfter(): float
    {
        return $this->realAfter;
    }
    
    public function getBonusBefore(): float
    {
        return $this->bonusBefore;
    }
    
    public function getBonusAfter(): float
    {
        return $this->bonusAfter;
    }
    
    public function getTotalBefore(): float
    {
        return $this->totalBefore;
    }
    
    public function getTotalAfter(): float
    {
        return $this->totalAfter;
    }
}