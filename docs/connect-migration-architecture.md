# Clean Architecture для Multi-Protocol Services

## Принципы

```
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  HTTP REST      │  │  Connect RPC    │  │  gRPC (future)  │  │
│  │  Controller     │  │  Handler        │  │  Handler        │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                    │           │
│           ▼                    ▼                    ▼           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Request/Response DTOs                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      APPLICATION LAYER                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      Use Cases                           │   │
│  │  - ValidateWagerUseCase                                  │   │
│  │  - PlaceWagerUseCase                                     │   │
│  │  - ProcessPaymentUseCase                                 │   │
│  │  - CalculateGameUseCase                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Port Interfaces                        │   │
│  │  - WagerRepositoryInterface                              │   │
│  │  - PaymentGatewayInterface                               │   │
│  │  - UserBalanceInterface                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DOMAIN LAYER                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Domain Entities                       │   │
│  │  - Wager, Bonus, Payment, GameResult                     │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Domain Services                        │   │
│  │  - WagerValidationService                                │   │
│  │  - BonusCalculationService                               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE LAYER                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  MongoDB        │  │  RabbitMQ       │  │  External APIs  │  │
│  │  Repository     │  │  Publisher      │  │  Clients        │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Ключевая идея: Protocol Adapters

**Бизнес-логика НЕ знает о протоколе!**

```
HTTP Controller ──┐
                  ├──▶ UseCase ──▶ Domain ──▶ Repository
Connect Handler ──┘
```

---

## 1. Payment Service (Node.js) - Референсная реализация

### Структура директорий

```
payment-service/
├── src/
│   ├── domain/                    # Domain Layer
│   │   ├── entities/
│   │   │   ├── Transaction.ts
│   │   │   └── Payment.ts
│   │   └── services/
│   │       └── PaymentValidation.ts
│   │
│   ├── application/               # Application Layer
│   │   ├── use-cases/
│   │   │   ├── ProcessPaymentUseCase.ts
│   │   │   └── TrackFinancialMetricsUseCase.ts
│   │   ├── dto/
│   │   │   ├── ProcessPaymentDTO.ts
│   │   │   └── FinancialMetricsDTO.ts
│   │   └── ports/
│   │       ├── UserRepositoryPort.ts
│   │       └── TransactionRepositoryPort.ts
│   │
│   ├── infrastructure/            # Infrastructure Layer
│   │   ├── persistence/
│   │   │   ├── MongoUserRepository.ts
│   │   │   └── MongoTransactionRepository.ts
│   │   ├── messaging/
│   │   │   └── RabbitMQPublisher.ts
│   │   └── metrics/
│   │       └── SentryMetrics.ts
│   │
│   ├── presentation/              # Presentation Layer (PROTOCOLS!)
│   │   ├── http/                  # REST API
│   │   │   ├── routes.ts
│   │   │   └── PaymentController.ts
│   │   └── connect/               # Connect RPC
│   │       └── PaymentHandlers.ts
│   │
│   ├── config/
│   │   └── container.ts           # DI Container
│   │
│   └── index.ts                   # Bootstrap
│
├── package.json
└── tsconfig.json
```

### Domain Layer

```typescript
// src/domain/entities/Payment.ts
export interface Payment {
  userId: string;
  bet: number;
  payout: number;
  netChange: number;
  type: 'WIN' | 'LOSS';
}

// src/domain/entities/Transaction.ts
export interface Transaction {
  id: string;
  userId: string;
  type: 'WIN' | 'LOSS';
  amount: number;
  bet: number;
  payout: number;
  balanceAfter: number;
  timestamp: Date;
}
```

### Application Layer - Use Cases

```typescript
// src/application/dto/ProcessPaymentDTO.ts
export interface ProcessPaymentInput {
  userId: string;
  bet: number;
  payout: number;
}

export interface ProcessPaymentOutput {
  success: boolean;
  newBalance: number;
  transactionId: string;
  transactionType: 'WIN' | 'LOSS';
}

// src/application/ports/UserRepositoryPort.ts
export interface UserRepositoryPort {
  findById(userId: string): Promise<User | null>;
  updateBalance(userId: string, change: number): Promise<User>;
  createWithBalance(userId: string, balance: number): Promise<User>;
}

// src/application/ports/TransactionRepositoryPort.ts
export interface TransactionRepositoryPort {
  create(transaction: Omit<Transaction, 'id'>): Promise<Transaction>;
}

// src/application/use-cases/ProcessPaymentUseCase.ts
export class ProcessPaymentUseCase {
  constructor(
    private userRepo: UserRepositoryPort,
    private transactionRepo: TransactionRepositoryPort,
    private messagePublisher: MessagePublisherPort
  ) {}

  async execute(input: ProcessPaymentInput): Promise<ProcessPaymentOutput> {
    const { userId, bet, payout } = input;
    const netChange = payout - bet;

    // Get or create user
    let user = await this.userRepo.findById(userId);
    if (!user) {
      user = await this.userRepo.createWithBalance(userId, 1000 + netChange);
    } else {
      user = await this.userRepo.updateBalance(userId, netChange);
    }

    // Record transaction
    const transaction = await this.transactionRepo.create({
      userId,
      type: netChange >= 0 ? 'WIN' : 'LOSS',
      amount: Math.abs(netChange),
      bet,
      payout,
      balanceAfter: user.balance,
      timestamp: new Date()
    });

    // Publish event (fire-and-forget)
    this.messagePublisher.publishPaymentEvent({
      type: netChange >= 0 ? 'credit' : 'debit',
      userId,
      amount: Math.abs(netChange),
      balanceAfter: user.balance
    }).catch(err => console.error('Failed to publish:', err));

    return {
      success: true,
      newBalance: user.balance,
      transactionId: transaction.id,
      transactionType: transaction.type
    };
  }
}
```

### Presentation Layer - HTTP Controller

```typescript
// src/presentation/http/PaymentController.ts
import { Request, Response } from 'express';
import { ProcessPaymentUseCase } from '../../application/use-cases/ProcessPaymentUseCase';

export class PaymentController {
  constructor(private processPayment: ProcessPaymentUseCase) {}

  async process(req: Request, res: Response): Promise<void> {
    try {
      const result = await this.processPayment.execute({
        userId: req.body.userId,
        bet: req.body.bet,
        payout: req.body.payout
      });

      res.json(result);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  }
}

// src/presentation/http/routes.ts
export function createHttpRoutes(app: Express, controller: PaymentController) {
  app.post('/process', (req, res) => controller.process(req, res));
  app.post('/financial-metrics', (req, res) => controller.trackMetrics(req, res));
}
```

### Presentation Layer - Connect Handler

```typescript
// src/presentation/connect/PaymentHandlers.ts
import { ConnectRouter } from '@connectrpc/connect';
import { PaymentService } from '@gitops-poc-dzha/payment-service-nodejs/payment/v1/payment_pb';
import { ProcessPaymentUseCase } from '../../application/use-cases/ProcessPaymentUseCase';

export function createConnectHandlers(
  processPayment: ProcessPaymentUseCase,
  trackMetrics: TrackFinancialMetricsUseCase
) {
  return (router: ConnectRouter) => {
    router.service(PaymentService, {
      async process(req) {
        // Same use case, different protocol!
        const result = await processPayment.execute({
          userId: req.userId,
          bet: req.bet,
          payout: req.payout
        });

        return {
          success: result.success,
          newBalance: result.newBalance,
          transactionId: result.transactionId,
          transactionType: result.transactionType
        };
      },

      async trackFinancialMetrics(req) {
        const result = await trackMetrics.execute({ scenario: req.scenario });
        return { status: result.status, metrics: result.metrics };
      }
    });
  };
}
```

### Bootstrap with DI

```typescript
// src/config/container.ts
import { ProcessPaymentUseCase } from '../application/use-cases/ProcessPaymentUseCase';
import { MongoUserRepository } from '../infrastructure/persistence/MongoUserRepository';
import { MongoTransactionRepository } from '../infrastructure/persistence/MongoTransactionRepository';
import { RabbitMQPublisher } from '../infrastructure/messaging/RabbitMQPublisher';

export function createContainer(db: Db) {
  // Infrastructure
  const userRepo = new MongoUserRepository(db);
  const transactionRepo = new MongoTransactionRepository(db);
  const messagePublisher = new RabbitMQPublisher();

  // Use Cases
  const processPayment = new ProcessPaymentUseCase(
    userRepo,
    transactionRepo,
    messagePublisher
  );
  const trackMetrics = new TrackFinancialMetricsUseCase();

  return { processPayment, trackMetrics };
}

// src/index.ts
import express from 'express';
import { expressConnectMiddleware } from '@connectrpc/connect-express';
import { createContainer } from './config/container';
import { createHttpRoutes } from './presentation/http/routes';
import { createConnectHandlers } from './presentation/connect/PaymentHandlers';
import { PaymentController } from './presentation/http/PaymentController';

const app = express();
app.use(express.json());

// Initialize container
const container = createContainer(db);

// Protocol: Connect RPC
app.use(expressConnectMiddleware({
  routes: createConnectHandlers(container.processPayment, container.trackMetrics)
}));

// Protocol: HTTP REST (legacy, can be disabled via config)
if (process.env.ENABLE_REST !== 'false') {
  const httpController = new PaymentController(container.processPayment);
  createHttpRoutes(app, httpController);
}

app.listen(8083);
```

---

## 2. Wager Service (PHP/Symfony)

### Структура директорий

```
wager-service/
├── src/
│   ├── Domain/                    # Domain Layer
│   │   ├── Entity/
│   │   │   ├── Wager.php
│   │   │   ├── Bonus.php
│   │   │   └── WageringProgress.php
│   │   ├── ValueObject/
│   │   │   ├── UserId.php
│   │   │   ├── Money.php
│   │   │   └── GameResult.php
│   │   └── Service/
│   │       └── WageringCalculator.php
│   │
│   ├── Application/               # Application Layer
│   │   ├── UseCase/
│   │   │   ├── Wager/
│   │   │   │   ├── ValidateWagerUseCase.php
│   │   │   │   ├── PlaceWagerUseCase.php
│   │   │   │   └── GetWagerHistoryUseCase.php
│   │   │   └── Bonus/
│   │   │       ├── ClaimBonusUseCase.php
│   │   │       ├── GetBonusProgressUseCase.php
│   │   │       └── ConvertBonusUseCase.php
│   │   ├── DTO/
│   │   │   ├── ValidateWagerRequest.php
│   │   │   ├── ValidateWagerResponse.php
│   │   │   └── ...
│   │   └── Port/
│   │       ├── WagerRepositoryInterface.php
│   │       ├── BonusRepositoryInterface.php
│   │       └── UserBalanceInterface.php
│   │
│   ├── Infrastructure/            # Infrastructure Layer
│   │   ├── Persistence/
│   │   │   ├── MongoWagerRepository.php
│   │   │   └── MongoBonusRepository.php
│   │   └── External/
│   │       └── UserServiceClient.php
│   │
│   └── Presentation/              # Presentation Layer
│       ├── Http/                  # REST Controllers
│       │   ├── WagerController.php
│       │   └── BonusController.php
│       └── Connect/               # Connect RPC
│           ├── ConnectWagerController.php
│           └── ConnectBonusController.php
│
├── config/
│   ├── services.yaml              # DI configuration
│   └── routes.yaml
└── composer.json
```

### Application Layer - Use Case

```php
<?php
// src/Application/DTO/ValidateWagerRequest.php
namespace App\Application\DTO;

final readonly class ValidateWagerRequest
{
    public function __construct(
        public string $userId,
        public float $amount,
        public string $gameId
    ) {}
}

// src/Application/DTO/ValidateWagerResponse.php
namespace App\Application\DTO;

final readonly class ValidateWagerResponse
{
    public function __construct(
        public bool $valid,
        public string $validationToken,
        public float $bonusUsed,
        public float $realUsed,
        public string $userId,
        public float $amount,
        public string $gameId
    ) {}

    public function toArray(): array
    {
        return [
            'valid' => $this->valid,
            'validationToken' => $this->validationToken,
            'bonusUsed' => $this->bonusUsed,
            'realUsed' => $this->realUsed,
            'userId' => $this->userId,
            'amount' => $this->amount,
            'gameId' => $this->gameId,
        ];
    }
}

// src/Application/UseCase/Wager/ValidateWagerUseCase.php
namespace App\Application\UseCase\Wager;

use App\Application\DTO\ValidateWagerRequest;
use App\Application\DTO\ValidateWagerResponse;
use App\Application\Port\BonusRepositoryInterface;
use App\Application\Port\UserBalanceInterface;

final class ValidateWagerUseCase
{
    public function __construct(
        private BonusRepositoryInterface $bonusRepo,
        private UserBalanceInterface $userBalance
    ) {}

    public function execute(ValidateWagerRequest $request): ValidateWagerResponse
    {
        // Get user's bonus and real balance
        $bonus = $this->bonusRepo->findActiveByUserId($request->userId);
        $realBalance = $this->userBalance->getBalance($request->userId);

        // Calculate how much to use from each
        $bonusUsed = 0.0;
        $realUsed = $request->amount;

        if ($bonus !== null && $bonus->balance > 0) {
            $bonusUsed = min($bonus->balance, $request->amount);
            $realUsed = $request->amount - $bonusUsed;
        }

        // Validate sufficient funds
        if ($realUsed > $realBalance) {
            return new ValidateWagerResponse(
                valid: false,
                validationToken: '',
                bonusUsed: 0,
                realUsed: 0,
                userId: $request->userId,
                amount: $request->amount,
                gameId: $request->gameId
            );
        }

        // Generate validation token
        $token = bin2hex(random_bytes(16));

        return new ValidateWagerResponse(
            valid: true,
            validationToken: $token,
            bonusUsed: $bonusUsed,
            realUsed: $realUsed,
            userId: $request->userId,
            amount: $request->amount,
            gameId: $request->gameId
        );
    }
}
```

### Presentation Layer - HTTP Controller

```php
<?php
// src/Presentation/Http/WagerController.php
namespace App\Presentation\Http;

use App\Application\DTO\ValidateWagerRequest;
use App\Application\UseCase\Wager\ValidateWagerUseCase;
use App\Application\UseCase\Wager\PlaceWagerUseCase;
use App\Application\UseCase\Wager\GetWagerHistoryUseCase;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/wager')]
class WagerController extends AbstractController
{
    public function __construct(
        private ValidateWagerUseCase $validateWager,
        private PlaceWagerUseCase $placeWager,
        private GetWagerHistoryUseCase $getHistory
    ) {}

    #[Route('/validate', methods: ['POST'])]
    public function validate(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        $response = $this->validateWager->execute(new ValidateWagerRequest(
            userId: $data['user_id'] ?? '',
            amount: (float)($data['amount'] ?? 0),
            gameId: $data['game_id'] ?? ''
        ));

        return $this->json($response->toArray());
    }

    // ... place, history methods
}
```

### Presentation Layer - Connect Controller

```php
<?php
// src/Presentation/Connect/ConnectWagerController.php
namespace App\Presentation\Connect;

use App\Application\DTO\ValidateWagerRequest;
use App\Application\UseCase\Wager\ValidateWagerUseCase;
use App\Application\UseCase\Wager\PlaceWagerUseCase;
use App\Application\UseCase\Wager\GetWagerHistoryUseCase;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

/**
 * Connect Protocol Controller
 * Same use cases, Connect-style routes!
 */
class ConnectWagerController extends AbstractController
{
    public function __construct(
        private ValidateWagerUseCase $validateWager,
        private PlaceWagerUseCase $placeWager,
        private GetWagerHistoryUseCase $getHistory
    ) {}

    #[Route('/wager.v1.WagerService/Validate', methods: ['POST'])]
    public function validate(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        // Same use case as HTTP controller!
        $response = $this->validateWager->execute(new ValidateWagerRequest(
            userId: $data['userId'] ?? '',      // camelCase from proto
            amount: (float)($data['amount'] ?? 0),
            gameId: $data['gameId'] ?? ''
        ));

        // Return camelCase for Connect protocol
        return $this->json([
            'valid' => $response->valid,
            'validationToken' => $response->validationToken,
            'bonusUsed' => $response->bonusUsed,
            'realUsed' => $response->realUsed,
            'userId' => $response->userId,
            'amount' => $response->amount,
            'gameId' => $response->gameId,
        ]);
    }

    #[Route('/wager.v1.WagerService/Place', methods: ['POST'])]
    public function place(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        $response = $this->placeWager->execute(new PlaceWagerRequest(
            validationData: $data['validationData'] ?? [],
            gameResult: $data['gameResult'] ?? '',
            payout: (float)($data['payout'] ?? 0)
        ));

        return $this->json([
            'wagerId' => $response->wagerId,
            'success' => $response->success,
            'wageringProgress' => $response->wageringProgress?->toArray(),
        ]);
    }

    #[Route('/wager.v1.WagerService/GetHistory', methods: ['POST'])]
    public function getHistory(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        $response = $this->getHistory->execute(new GetHistoryRequest(
            userId: $data['userId'] ?? '',
            limit: (int)($data['limit'] ?? 10)
        ));

        return $this->json([
            'wagers' => $response->wagers,
            'totalCount' => $response->totalCount,
        ]);
    }
}
```

### DI Configuration

```yaml
# config/services.yaml
services:
  _defaults:
    autowire: true
    autoconfigure: true

  # Use Cases
  App\Application\UseCase\:
    resource: '../src/Application/UseCase/'

  # Both controllers use the SAME use cases!
  App\Presentation\Http\:
    resource: '../src/Presentation/Http/'

  App\Presentation\Connect\:
    resource: '../src/Presentation/Connect/'
```

---

## 3. Game Engine (Python)

### Структура директорий

```
game-engine/
├── src/
│   ├── domain/                    # Domain Layer
│   │   ├── entities.py            # GameResult, Symbol
│   │   └── services.py            # SlotMachineService
│   │
│   ├── application/               # Application Layer
│   │   ├── use_cases/
│   │   │   ├── calculate_game.py
│   │   │   └── track_metrics.py
│   │   ├── dto.py
│   │   └── ports.py               # Repository interfaces
│   │
│   ├── infrastructure/            # Infrastructure Layer
│   │   ├── persistence/
│   │   │   └── mongo_repository.py
│   │   ├── messaging/
│   │   │   └── rabbitmq_publisher.py
│   │   └── metrics/
│   │       └── sentry_metrics.py
│   │
│   ├── presentation/              # Presentation Layer
│   │   ├── http/                  # REST (Tornado)
│   │   │   └── handlers.py
│   │   └── connect/               # Connect RPC
│   │       └── handlers.py
│   │
│   └── container.py               # DI Container
│
├── main.py                        # Bootstrap
└── requirements.txt
```

### Application Layer

```python
# src/application/dto.py
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class CalculateGameRequest:
    user_id: str
    bet: float
    cpu_intensive: bool = False

@dataclass
class WageringProgress:
    progress_percent: float
    remaining: float
    can_convert: bool

@dataclass
class CalculateGameResponse:
    win: bool
    payout: float
    symbols: List[str]
    new_balance: float
    wagering_progress: Optional[WageringProgress] = None

# src/application/use_cases/calculate_game.py
from ..dto import CalculateGameRequest, CalculateGameResponse
from ..ports import GameRepositoryPort, UserBalancePort
from ...domain.services import SlotMachineService

class CalculateGameUseCase:
    def __init__(
        self,
        slot_machine: SlotMachineService,
        game_repo: GameRepositoryPort,
        user_balance: UserBalancePort
    ):
        self.slot_machine = slot_machine
        self.game_repo = game_repo
        self.user_balance = user_balance

    async def execute(self, request: CalculateGameRequest) -> CalculateGameResponse:
        # Calculate game result
        if request.cpu_intensive:
            result = self.slot_machine.calculate_cpu_intensive()
        else:
            result = self.slot_machine.calculate_normal()

        # Calculate payout
        payout = request.bet * result.multiplier if result.win else 0

        # Update balance
        new_balance = await self.user_balance.update(
            request.user_id,
            bet=request.bet,
            payout=payout
        )

        # Save game record
        await self.game_repo.save({
            'user_id': request.user_id,
            'bet': request.bet,
            'win': result.win,
            'payout': payout,
            'symbols': result.symbols
        })

        return CalculateGameResponse(
            win=result.win,
            payout=payout,
            symbols=result.symbols,
            new_balance=new_balance
        )
```

### Presentation Layer - Both Protocols

```python
# src/presentation/http/handlers.py
from tornado import web
from ...application.use_cases.calculate_game import CalculateGameUseCase
from ...application.dto import CalculateGameRequest

class CalculateHandler(web.RequestHandler):
    def initialize(self, use_case: CalculateGameUseCase):
        self.use_case = use_case

    async def post(self):
        data = json.loads(self.request.body)

        result = await self.use_case.execute(CalculateGameRequest(
            user_id=data.get('userId'),
            bet=data.get('bet'),
            cpu_intensive=data.get('cpu_intensive', False)
        ))

        self.write({
            'win': result.win,
            'payout': result.payout,
            'symbols': result.symbols,
            'newBalance': result.new_balance
        })

# src/presentation/connect/handlers.py
from tornado import web
from ...application.use_cases.calculate_game import CalculateGameUseCase
from ...application.dto import CalculateGameRequest

class ConnectCalculateHandler(web.RequestHandler):
    """Connect Protocol handler - same use case!"""

    def initialize(self, use_case: CalculateGameUseCase):
        self.use_case = use_case

    async def post(self):
        data = json.loads(self.request.body)

        # Same use case, Connect-style field names
        result = await self.use_case.execute(CalculateGameRequest(
            user_id=data.get('userId'),
            bet=data.get('bet'),
            cpu_intensive=data.get('cpuIntensive', False)
        ))

        self.set_header('Content-Type', 'application/json')
        self.write({
            'win': result.win,
            'payout': result.payout,
            'symbols': result.symbols,
            'newBalance': result.new_balance
        })

# main.py
def make_app(container):
    return web.Application([
        # HTTP REST
        (r"/health", HealthHandler),
        (r"/calculate", CalculateHandler, {'use_case': container.calculate_game}),
        (r"/business-metrics", BusinessMetricsHandler, {'use_case': container.track_metrics}),

        # Connect Protocol (same use cases!)
        (r"/game.v1.GameEngineService/Calculate", ConnectCalculateHandler,
            {'use_case': container.calculate_game}),
        (r"/game.v1.GameEngineService/TrackBusinessMetrics", ConnectBusinessMetricsHandler,
            {'use_case': container.track_metrics}),
    ])
```

---

## Переключение протоколов

### Через Environment Variable

```bash
# Включить только Connect
ENABLE_REST=false
ENABLE_CONNECT=true

# Включить оба (переходный период)
ENABLE_REST=true
ENABLE_CONNECT=true

# Только REST (legacy)
ENABLE_REST=true
ENABLE_CONNECT=false
```

### Через Feature Flag

```typescript
// Node.js
if (config.protocols.connect) {
  app.use(expressConnectMiddleware({ routes: connectHandlers }));
}
if (config.protocols.rest) {
  createHttpRoutes(app, httpController);
}
```

```php
// PHP - services.yaml
parameters:
  enable_connect: '%env(bool:ENABLE_CONNECT)%'
  enable_rest: '%env(bool:ENABLE_REST)%'
```

---

## Резюме: Что получаем

| Принцип | Реализация |
|---------|------------|
| **Clean Architecture** | Domain → Application → Infrastructure, Presentation |
| **SOLID - SRP** | Use Case = одна бизнес-операция |
| **SOLID - OCP** | Новый протокол = новый адаптер, use cases не меняются |
| **SOLID - DIP** | Use cases зависят от интерфейсов (Ports) |
| **DRY** | Бизнес-логика в use cases, не дублируется в контроллерах |
| **KISS** | Простые DTO, простые адаптеры |
| **YAGNI** | Добавляем только то что нужно сейчас |

**Ключевое преимущество**: Добавление нового протокола (gRPC, GraphQL, WebSocket) = только новый адаптер в Presentation layer!
