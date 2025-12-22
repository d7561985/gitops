import * as Sentry from '@sentry/angular';
import type { Span } from '@sentry/angular';

/**
 * Creates an independent Sentry transaction that is not nested within pageload/navigation
 * @param name - Transaction name (e.g., 'user-action.slot-machine.spin')
 * @param operation - Operation type (e.g., 'user-action', 'http', 'db')
 * @param attributes - Custom attributes to attach to the transaction
 * @param callback - Async function to execute within the transaction context
 * @returns Promise with the result of the callback
 */
export async function createIndependentTransaction<T>(
  name: string,
  operation: string,
  attributes: Record<string, any>,
  callback: (span: Span | undefined) => Promise<T>
): Promise<T> {
  return Sentry.startSpan(
    {
      name,
      op: operation,
      forceTransaction: true, // Force this span to be a transaction
      attributes
    },
    callback
  );
}

/**
 * Creates a completely new trace context, breaking from any parent spans
 * @param name - Transaction name
 * @param operation - Operation type
 * @param callback - Async function to execute within the new trace context
 * @returns Promise with the result of the callback
 */
export async function createNewTrace<T>(
  name: string,
  operation: string,
  callback: (span: Span | undefined) => Promise<T>
): Promise<T> {
  // Сначала заканчиваем любую активную транзакцию pageload/navigation
  const activeSpan = Sentry.getActiveSpan();
  if (activeSpan) {
    const rootSpan = Sentry.getRootSpan(activeSpan);
    const rootOp = rootSpan ? (rootSpan as any).op : undefined;
    
    // Если есть активная pageload/navigation транзакция, завершаем её
    if (rootOp === 'pageload' || rootOp === 'navigation') {
      console.log('[Sentry] Finishing pageload/navigation transaction before creating new trace');
      (rootSpan as any).end();
    }
  }
  
  // Создаем полностью новый контекст трейса
  return Sentry.withScope((scope) => {
    // Очищаем любой существующий контекст
    scope.clearBreadcrumbs();
    // В SDK v9 используем clear() вместо setSpan(undefined)
    scope.clear();
    
    // Создаем новую транзакцию без родителя
    return Sentry.startSpan(
      {
        name,
        op: operation,
        forceTransaction: true
        // parentSpanId и traceId не поддерживаются в SDK v9
        // forceTransaction уже создает новый trace
      },
      callback
    );
  });
}

/**
 * Standard naming conventions for different action types
 */
export const TransactionNames = {
  // Slot machine actions
  SLOT_SPIN: 'user-action.slot-machine.spin',
  SLOT_DEBUG_CPU: 'user-action.slot-machine.debug-cpu-spike',
  SLOT_DEBUG_N1: 'user-action.slot-machine.debug-n1-query',
  SLOT_DEBUG_PANIC: 'user-action.slot-machine.debug-gateway-panic',
  SLOT_DEBUG_AUTH: 'user-action.slot-machine.debug-auth-error',
  SLOT_DEBUG_AGGREGATION: 'user-action.slot-machine.debug-slow-aggregation',
  SLOT_DEBUG_PROMISE: 'user-action.slot-machine.debug-promise-rejection',
  SLOT_DEBUG_ERROR: 'user-action.slot-machine.debug-component-error',
  
  // Business metrics actions
  METRICS_REFRESH: 'user-action.metrics.refresh',
  METRICS_SCENARIO: 'user-action.metrics.scenario',
  
  // Payment actions (future)
  PAYMENT_DEPOSIT: 'user-action.payment.deposit',
  PAYMENT_WITHDRAW: 'user-action.payment.withdraw',
  
  // Auth actions (future)
  AUTH_LOGIN: 'user-action.auth.login',
  AUTH_REGISTER: 'user-action.auth.register',
  AUTH_LOGOUT: 'user-action.auth.logout'
} as const;

/**
 * Standard operation types
 */
export const Operations = {
  USER_ACTION: 'user-action',
  DEBUG: 'debug',
  HTTP: 'http',
  DB: 'db',
  CACHE: 'cache',
  UI: 'ui'
} as const;

/**
 * Helper to set transaction status based on result
 */
export function setTransactionStatus(
  span: Span | undefined,
  success: boolean,
  error?: Error
): void {
  if (!span) return;
  
  if (success) {
    span.setStatus({ code: 1 }); // SpanStatusCode.OK = 1
  } else if (error) {
    span.setStatus({ code: 2 }); // SpanStatusCode.ERROR = 2
    span.setAttribute('error', true);
    span.setAttribute('error.message', error.message);
  } else {
    span.setStatus({ code: 2 }); // SpanStatusCode.ERROR = 2
  }
}

