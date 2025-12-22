<?php

namespace App\Document;

use Doctrine\ODM\MongoDB\Mapping\Annotations as ODM;
use Doctrine\ODM\MongoDB\Types\Type;

#[ODM\Document(collection: "bonus_conversions")]
#[ODM\Index(keys: ["userId" => 1])]
#[ODM\Index(keys: ["conversionCompletedAt" => -1])]
class BonusConversion
{
    #[ODM\Id]
    private ?string $id = null;
    
    #[ODM\Field(type: Type::STRING)]
    private string $userId;
    
    #[ODM\Field(type: Type::STRING)]
    private string $bonusId;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $bonusAmount;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $totalWagered;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $conversionRate = 1.0; // 100% converted
    
    #[ODM\Field(type: Type::DATE)]
    private \DateTimeInterface $bonusCreatedAt;
    
    #[ODM\Field(type: Type::DATE)]
    private \DateTimeInterface $conversionCompletedAt;
    
    #[ODM\Field(type: Type::INT)]
    private int $durationMinutes;
    
    #[ODM\Field(type: Type::INT)]
    private int $totalWagers;
    
    #[ODM\Field(type: Type::INT)]
    private int $winningWagers;
    
    #[ODM\Field(type: Type::FLOAT)]
    private float $winRate;
    
    public function __construct(
        string $userId,
        string $bonusId,
        float $bonusAmount,
        float $totalWagered,
        \DateTimeInterface $bonusCreatedAt
    ) {
        $this->userId = $userId;
        $this->bonusId = $bonusId;
        $this->bonusAmount = $bonusAmount;
        $this->totalWagered = $totalWagered;
        $this->bonusCreatedAt = $bonusCreatedAt;
        $this->conversionCompletedAt = new \DateTime();
        
        // Calculate duration in minutes
        $interval = $this->conversionCompletedAt->diff($bonusCreatedAt);
        $this->durationMinutes = ($interval->days * 24 * 60) + ($interval->h * 60) + $interval->i;
    }
    
    public function getId(): ?string
    {
        return $this->id;
    }
    
    public function getUserId(): string
    {
        return $this->userId;
    }
    
    public function getBonusId(): string
    {
        return $this->bonusId;
    }
    
    public function getBonusAmount(): float
    {
        return $this->bonusAmount;
    }
    
    public function getTotalWagered(): float
    {
        return $this->totalWagered;
    }
    
    public function getConversionRate(): float
    {
        return $this->conversionRate;
    }
    
    public function getBonusCreatedAt(): \DateTimeInterface
    {
        return $this->bonusCreatedAt;
    }
    
    public function getConversionCompletedAt(): \DateTimeInterface
    {
        return $this->conversionCompletedAt;
    }
    
    public function getDurationMinutes(): int
    {
        return $this->durationMinutes;
    }
    
    public function getTotalWagers(): int
    {
        return $this->totalWagers;
    }
    
    public function setTotalWagers(int $totalWagers): self
    {
        $this->totalWagers = $totalWagers;
        $this->calculateWinRate();
        return $this;
    }
    
    public function getWinningWagers(): int
    {
        return $this->winningWagers;
    }
    
    public function setWinningWagers(int $winningWagers): self
    {
        $this->winningWagers = $winningWagers;
        $this->calculateWinRate();
        return $this;
    }
    
    public function getWinRate(): float
    {
        return $this->winRate;
    }
    
    private function calculateWinRate(): void
    {
        if ($this->totalWagers > 0) {
            $this->winRate = $this->winningWagers / $this->totalWagers;
        } else {
            $this->winRate = 0.0;
        }
    }
}