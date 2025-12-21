# Connect Protocol Migration Plan

## Обзор

Миграция трёх sentry-demo сервисов с HTTP REST на Connect Protocol.

| Сервис | Язык | Connect Support | Сложность |
|--------|------|-----------------|-----------|
| game-engine | Python/Tornado | Alpha (`connect-python`) | Средняя |
| payment-service | Node.js/Express | Полная (`@connectrpc/connect-node`) | Низкая |
| wager-service | PHP/Symfony | Нет официальной | Средняя* |

> *PHP: Connect = HTTP POST + JSON. Можно реализовать без спец. библиотеки!

---

## 1. Payment Service (Node.js) - РЕКОМЕНДУЮ НАЧАТЬ С НЕГО

**Почему первым**: Полная официальная поддержка, минимум изменений.

### 1.1 Установка зависимостей

```bash
cd services/sentry-demo/payment-service
npm install @connectrpc/connect @connectrpc/connect-node @connectrpc/connect-express
npm install @gitops-poc-dzha/payment-service-nodejs  # сгенерированный код
```

### 1.2 Создание Connect handlers

```javascript
// src/connect/payment-handlers.js
import { PaymentService } from '@gitops-poc-dzha/payment-service-nodejs/payment/v1/payment_pb';

export const paymentHandlers = (router) => {
  router.service(PaymentService, {
    async process(req) {
      const { userId, bet, payout } = req;
      // ... существующая логика из /process endpoint
      return {
        success: true,
        newBalance: result.value.balance,
        transactionId: transaction._id,
        transactionType: netChange >= 0 ? 'WIN' : 'LOSS'
      };
    },

    async trackFinancialMetrics(req) {
      const { scenario } = req;
      // ... существующая логика из /financial-metrics
      return { status: 'ok', metrics: {} };
    }
  });
};
```

### 1.3 Интеграция с Express

```javascript
// index.js (добавить)
import { expressConnectMiddleware } from '@connectrpc/connect-express';
import { paymentHandlers } from './connect/payment-handlers.js';

// После app.use(express.json())
app.use(expressConnectMiddleware({
  routes: paymentHandlers
}));

// Существующие REST endpoints остаются для обратной совместимости
```

### 1.4 Тестирование

```bash
# Connect вызов
curl -X POST http://localhost:8083/payment.v1.PaymentService/Process \
  -H "Content-Type: application/json" \
  -H "Connect-Protocol-Version: 1" \
  -d '{"userId":"test","bet":10,"payout":0}'
```

---

## 2. Game Engine (Python)

**Особенность**: Tornado не поддерживается connect-python напрямую. Два варианта:

### Вариант A: Параллельные endpoints (рекомендую)

Добавить Connect-style роуты в существующий Tornado, обрабатывать как обычный HTTP POST.

```python
# main.py - добавить

class ConnectCalculateHandler(web.RequestHandler):
    """Connect protocol handler for GameEngineService.Calculate"""

    async def post(self):
        # Проверяем Connect protocol header
        if self.request.headers.get('Connect-Protocol-Version') != '1':
            # Fallback to regular handling
            pass

        data = json.loads(self.request.body)
        # Используем ту же логику что и CalculateHandler
        result = await self._calculate(data)

        self.set_header('Content-Type', 'application/json')
        self.write(result)

# В make_app() добавить:
(r"/game.v1.GameEngineService/Calculate", ConnectCalculateHandler),
(r"/game.v1.GameEngineService/TrackBusinessMetrics", ConnectBusinessMetricsHandler),
```

### Вариант B: Использовать connect-python (alpha)

```bash
pip install connect-python
```

```python
# Требует ASGI сервер (uvicorn, hypercorn)
# Нужно переписать на ASGI вместо Tornado
from connect.server import Server
from gen.game.v1 import game_pb2

# ... более сложная миграция
```

**Рекомендация**: Вариант A - минимальные изменения, быстрый результат.

---

## 3. Wager Service (PHP/Symfony) - ВАЖНО!

**Ключевой инсайт**: Connect Protocol = HTTP POST + JSON. PHP отлично справляется!

### 3.1 Понимание Connect Protocol

```
POST /wager.v1.WagerService/Validate
Content-Type: application/json
Connect-Protocol-Version: 1

{"userId":"123","amount":100,"gameId":"slot-machine"}
```

Это обычный HTTP POST! Symfony может обработать без проблем.

### 3.2 Создание Connect Controller

```php
<?php
// src/Controller/ConnectController.php

namespace App\Controller;

use App\Service\WagerService;
use App\Service\BonusService;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

/**
 * Connect Protocol handlers for WagerService and BonusService
 *
 * Connect Protocol = HTTP POST + JSON, no special library needed!
 */
class ConnectController extends AbstractController
{
    public function __construct(
        private WagerService $wagerService,
        private BonusService $bonusService
    ) {}

    // ==================== WagerService ====================

    #[Route('/wager.v1.WagerService/Validate', methods: ['POST'])]
    public function wagerValidate(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->wagerService->validateWager(
                $data['userId'] ?? '',
                $data['amount'] ?? 0,
                $data['gameId'] ?? ''
            );

            return $this->connectResponse([
                'valid' => $result['valid'] ?? true,
                'validationToken' => $result['validation_token'] ?? '',
                'bonusUsed' => $result['bonus_used'] ?? 0,
                'realUsed' => $result['real_used'] ?? 0,
                'userId' => $data['userId'],
                'amount' => $data['amount'],
                'gameId' => $data['gameId']
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.WagerService/Place', methods: ['POST'])]
    public function wagerPlace(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->wagerService->placeWager(
                $data['validationData'] ?? [],
                $data['gameResult'] ?? '',
                $data['payout'] ?? 0
            );

            return $this->connectResponse([
                'wagerId' => $result['wager_id'] ?? '',
                'success' => true,
                'wageringProgress' => [
                    'progressPercent' => $result['wagering_progress']['progress'] ?? 0,
                    'remaining' => $result['wagering_progress']['remaining'] ?? 0,
                    'canConvert' => $result['wagering_progress']['can_convert'] ?? false
                ]
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.WagerService/GetHistory', methods: ['POST'])]
    public function wagerGetHistory(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->wagerService->getWagerHistory(
                $data['userId'] ?? '',
                $data['limit'] ?? 10
            );

            return $this->connectResponse([
                'wagers' => $result['wagers'] ?? [],
                'totalCount' => $result['total_count'] ?? 0
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    // ==================== BonusService ====================

    #[Route('/wager.v1.BonusService/Claim', methods: ['POST'])]
    public function bonusClaim(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->bonusService->claimWelcomeBonus(
                $data['userId'] ?? '',
                $request
            );

            return $this->connectResponse([
                'success' => true,
                'bonusId' => $result['bonus_id'] ?? '',
                'amount' => $result['amount'] ?? 0,
                'wageringMultiplier' => $result['wagering_multiplier'] ?? 35,
                'wageringRequired' => $result['wagering_required'] ?? 0,
                'expiresAt' => $result['expires_at'] ?? ''
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.BonusService/GetProgress', methods: ['POST'])]
    public function bonusGetProgress(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->bonusService->getProgress($data['userId'] ?? '');

            return $this->connectResponse([
                'hasActiveBonus' => $result['has_active_bonus'] ?? false,
                'bonusBalance' => $result['bonus_balance'] ?? 0,
                'realBalance' => $result['real_balance'] ?? 0,
                'progressPercent' => $result['progress_percent'] ?? 0,
                'wageringRequired' => $result['wagering_required'] ?? 0,
                'wageredAmount' => $result['wagered_amount'] ?? 0,
                'remaining' => $result['remaining'] ?? 0,
                'canConvert' => $result['can_convert'] ?? false,
                'expiresAt' => $result['expires_at'] ?? ''
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    #[Route('/wager.v1.BonusService/Convert', methods: ['POST'])]
    public function bonusConvert(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        try {
            $result = $this->bonusService->convertBonusToReal($data['userId'] ?? '');

            return $this->connectResponse([
                'success' => true,
                'convertedAmount' => $result['converted_amount'] ?? 0,
                'newBalance' => $result['new_balance'] ?? 0
            ]);
        } catch (\Exception $e) {
            return $this->connectError($e);
        }
    }

    // ==================== Helpers ====================

    private function connectResponse(array $data): JsonResponse
    {
        $response = new JsonResponse($data);
        $response->headers->set('Content-Type', 'application/json');
        return $response;
    }

    private function connectError(\Exception $e): JsonResponse
    {
        // Connect protocol error format
        return new JsonResponse([
            'code' => $this->mapExceptionToConnectCode($e),
            'message' => $e->getMessage()
        ], $this->getHttpStatusFromException($e));
    }

    private function mapExceptionToConnectCode(\Exception $e): string
    {
        // Map to Connect error codes
        return match(true) {
            $e instanceof \InvalidArgumentException => 'invalid_argument',
            $e instanceof \RuntimeException => 'internal',
            default => 'unknown'
        };
    }

    private function getHttpStatusFromException(\Exception $e): int
    {
        $code = $e->getCode();
        return ($code >= 400 && $code < 600) ? $code : 500;
    }
}
```

### 3.3 Обновление маршрутов

```yaml
# config/routes.yaml (если нужно)
# Аннотации в контроллере уже определяют маршруты
```

### 3.4 Опционально: Middleware для заголовков

```php
<?php
// src/EventSubscriber/ConnectProtocolSubscriber.php

namespace App\EventSubscriber;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\Event\ResponseEvent;
use Symfony\Component\HttpKernel\KernelEvents;

class ConnectProtocolSubscriber implements EventSubscriberInterface
{
    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::REQUEST => 'onRequest',
            KernelEvents::RESPONSE => 'onResponse',
        ];
    }

    public function onRequest(RequestEvent $event): void
    {
        $request = $event->getRequest();

        // Check if this is a Connect protocol request
        $path = $request->getPathInfo();
        if (preg_match('/^\/wager\.v1\.(Wager|Bonus)Service\//', $path)) {
            // Mark as Connect request for logging/metrics
            $request->attributes->set('_connect_protocol', true);
        }
    }

    public function onResponse(ResponseEvent $event): void
    {
        $request = $event->getRequest();

        if ($request->attributes->get('_connect_protocol')) {
            $response = $event->getResponse();
            // Ensure proper Content-Type
            $response->headers->set('Content-Type', 'application/json');
        }
    }
}
```

---

## Порядок миграции

```
┌─────────────────────────────────────────────────────────────┐
│  1. Payment Service (Node.js)                               │
│     - Официальная поддержка                                 │
│     - Быстрая интеграция                                    │
│     - Валидация подхода                                     │
├─────────────────────────────────────────────────────────────┤
│  2. Wager Service (PHP)                                     │
│     - Connect = HTTP POST + JSON                            │
│     - Symfony контроллеры                                   │
│     - Никаких спец. библиотек                               │
├─────────────────────────────────────────────────────────────┤
│  3. Game Engine (Python)                                    │
│     - Параллельные endpoints в Tornado                      │
│     - Или миграция на connect-python (alpha)                │
└─────────────────────────────────────────────────────────────┘
```

---

## После миграции сервисов

### Обновление API Gateway

```yaml
# config.yaml - добавить Connect endpoints

# Game Engine - Connect protocol
- name: game-connect
  cluster: sentry-game-engine
  auth: {policy: no-need}
  methods:
    - name: game.v1.GameEngineService/Calculate
      auth: {policy: no-need}
    - name: game.v1.GameEngineService/TrackBusinessMetrics
      auth: {policy: no-need}

# Payment - Connect protocol
- name: payment-connect
  cluster: sentry-payment
  auth: {policy: no-need}
  methods:
    - name: payment.v1.PaymentService/Process
      auth: {policy: no-need}
    - name: payment.v1.PaymentService/TrackFinancialMetrics
      auth: {policy: no-need}

# Wager - Connect protocol
- name: wager-connect
  cluster: sentry-wager
  auth: {policy: no-need}
  methods:
    - name: wager.v1.WagerService/Validate
      auth: {policy: no-need}
    - name: wager.v1.WagerService/Place
      auth: {policy: no-need}
    - name: wager.v1.WagerService/GetHistory
      auth: {policy: no-need}
    - name: wager.v1.BonusService/Claim
      auth: {policy: no-need}
    - name: wager.v1.BonusService/GetProgress
      auth: {policy: no-need}
    - name: wager.v1.BonusService/Convert
      auth: {policy: no-need}
```

### Обновление Frontend

```typescript
// Добавить в frontend зависимости
npm install @gitops-poc-dzha/game-engine-web
npm install @gitops-poc-dzha/payment-service-web
npm install @gitops-poc-dzha/wager-service-web

// Использование (пример для game-engine)
import { createClient } from '@connectrpc/connect';
import { createConnectTransport } from '@connectrpc/connect-web';
import { GameEngineService } from '@gitops-poc-dzha/game-engine-web/game/v1/game_pb';

const transport = createConnectTransport({
  baseUrl: '/api/game-connect'
});

const client = createClient(GameEngineService, transport);

// Type-safe RPC call!
const result = await client.calculate({
  userId: 'user123',
  bet: 10,
  cpuIntensive: false
});
```

---

## Источники

- [Connect Protocol](https://connectrpc.com/docs/protocol/)
- [Connect Node.js](https://connectrpc.com/docs/node/getting-started)
- [Choosing a Protocol](https://connectrpc.com/docs/web/choosing-a-protocol/)
