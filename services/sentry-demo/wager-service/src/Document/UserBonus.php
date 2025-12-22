<?php

namespace App\Document;

use Doctrine\ODM\MongoDB\Mapping\Annotations as ODM;
use Doctrine\ODM\MongoDB\Types\Type;

#[ODM\Document(collection: "user_bonuses")]
#[ODM\Index(keys: ["_id" => 1])]
class UserBonus
{
    #[ODM\Id(strategy: "NONE")]
    private string $id; // Using user_id as _id for O(1) lookups
    
    #[ODM\EmbedOne(targetDocument: ActiveBonus::class)]
    private ?ActiveBonus $activeBonus = null;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $realBalance = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $bonusBalance = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $totalBalance = 0.0;
    
    #[ODM\Field(type: Type::INT)]
    private int $totalBonusesClaimed = 0;
    
    #[ODM\Field(type: Type::INT)]
    private int $totalBonusesCompleted = 0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $lifetimeWagered = 0.0;
    
    #[ODM\Field(type: Type::INT)]
    private int $version = 1;
    
    #[ODM\Field(type: Type::DATE)]
    private ?\DateTimeInterface $lastWagerTime = null;
    
    public function __construct(string $userId)
    {
        $this->id = $userId;
    }
    
    public function getId(): string
    {
        return $this->id;
    }
    
    public function getActiveBonus(): ?ActiveBonus
    {
        return $this->activeBonus;
    }
    
    public function setActiveBonus(?ActiveBonus $activeBonus): self
    {
        $this->activeBonus = $activeBonus;
        if ($activeBonus) {
            $this->bonusBalance = $activeBonus->getAmount();
            $this->updateTotalBalance();
        }
        return $this;
    }
    
    public function getRealBalance(): float
    {
        return $this->realBalance;
    }
    
    public function setRealBalance(float $realBalance): self
    {
        $this->realBalance = $realBalance;
        $this->updateTotalBalance();
        return $this;
    }
    
    public function getBonusBalance(): float
    {
        return $this->bonusBalance;
    }
    
    public function setBonusBalance(float $bonusBalance): self
    {
        $this->bonusBalance = $bonusBalance;
        $this->updateTotalBalance();
        return $this;
    }
    
    public function getTotalBalance(): float
    {
        return $this->totalBalance;
    }
    
    private function updateTotalBalance(): void
    {
        $this->totalBalance = $this->realBalance + $this->bonusBalance;
    }
    
    public function getTotalBonusesClaimed(): int
    {
        return $this->totalBonusesClaimed;
    }
    
    public function incrementBonusesClaimed(): self
    {
        $this->totalBonusesClaimed++;
        return $this;
    }
    
    public function getTotalBonusesCompleted(): int
    {
        return $this->totalBonusesCompleted;
    }
    
    public function incrementBonusesCompleted(): self
    {
        $this->totalBonusesCompleted++;
        return $this;
    }
    
    public function getLifetimeWagered(): float
    {
        return $this->lifetimeWagered;
    }
    
    public function addToLifetimeWagered(float $amount): self
    {
        $this->lifetimeWagered += $amount;
        return $this;
    }
    
    public function getVersion(): int
    {
        return $this->version;
    }
    
    public function incrementVersion(): self
    {
        $this->version++;
        return $this;
    }
    
    public function getLastWagerTime(): ?\DateTimeInterface
    {
        return $this->lastWagerTime;
    }
    
    public function setLastWagerTime(\DateTimeInterface $lastWagerTime): self
    {
        $this->lastWagerTime = $lastWagerTime;
        return $this;
    }
    
    public function canWager(float $amount): bool
    {
        return $this->totalBalance >= $amount;
    }
    
    public function calculateBalanceDeduction(float $amount): array
    {
        $bonusUsed = min($amount, $this->bonusBalance);
        $realUsed = $amount - $bonusUsed;
        
        return [
            'bonus_used' => $bonusUsed,
            'real_used' => $realUsed,
            'sufficient' => $realUsed <= $this->realBalance
        ];
    }
}

#[ODM\EmbeddedDocument]
class ActiveBonus
{
    #[ODM\Field(type: Type::STRING)]
    private string $id;
    
    #[ODM\Field(type: Type::STRING)]
    private string $type = 'welcome';
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $amount;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $wageringRequired;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $wageringCompleted = 0.0;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $progressPercentage = 0.0;
    
    #[ODM\Field(type: Type::STRING)]
    private string $status = 'active'; // active, completed, expired
    
    #[ODM\Field(type: Type::DATE)]
    private \DateTimeInterface $createdAt;
    
    #[ODM\Field(type: Type::DATE, nullable: true)]
    private ?\DateTimeInterface $expiresAt = null;
    
    #[ODM\Field(type: Type::DATE)]
    private \DateTimeInterface $lastUpdated;
    
    public function __construct(float $amount, float $multiplier = 2.0)
    {
        $this->id = 'welcome-bonus-' . date('Y-m-d-His');
        $this->amount = $amount;
        $this->wageringRequired = $amount * $multiplier;
        $this->createdAt = new \DateTime();
        $this->lastUpdated = new \DateTime();
    }
    
    public function getId(): string
    {
        return $this->id;
    }
    
    public function getType(): string
    {
        return $this->type;
    }
    
    public function getAmount(): float
    {
        return $this->amount;
    }
    
    public function getWageringRequired(): float
    {
        return $this->wageringRequired;
    }
    
    public function getWageringCompleted(): float
    {
        return $this->wageringCompleted;
    }
    
    public function addWageringProgress(float $amount): self
    {
        $this->wageringCompleted += $amount;
        $this->progressPercentage = min(100, ($this->wageringCompleted / $this->wageringRequired) * 100);
        $this->lastUpdated = new \DateTime();
        
        if ($this->wageringCompleted >= $this->wageringRequired) {
            $this->status = 'completed';
        }
        
        return $this;
    }
    
    public function getProgressPercentage(): float
    {
        return $this->progressPercentage;
    }
    
    public function getStatus(): string
    {
        return $this->status;
    }
    
    public function setStatus(string $status): self
    {
        $this->status = $status;
        return $this;
    }
    
    public function isActive(): bool
    {
        return $this->status === 'active';
    }
    
    public function isComplete(): bool
    {
        return $this->wageringCompleted >= $this->wageringRequired;
    }
    
    public function getCreatedAt(): \DateTimeInterface
    {
        return $this->createdAt;
    }
    
    public function getExpiresAt(): ?\DateTimeInterface
    {
        return $this->expiresAt;
    }
    
    public function getLastUpdated(): \DateTimeInterface
    {
        return $this->lastUpdated;
    }
}