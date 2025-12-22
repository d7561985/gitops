import { bootstrapApplication } from '@angular/platform-browser';
import { enableProdMode } from '@angular/core';
import * as Sentry from '@sentry/angular';

import { AppComponent } from './app/app.component';
import { appConfig } from './app.config';
import { environment } from './environments/environment';

// Initialize Sentry SDK v9 with Session Replay
// Полная конфигурация с комментариями о всех доступных опциях
Sentry.init({
  // === ОБЯЗАТЕЛЬНЫЕ НАСТРОЙКИ ===
  // DSN (Data Source Name) - уникальный идентификатор вашего проекта в Sentry
  dsn: environment.sentryDsn,
  
  // === ИНФОРМАЦИЯ О РЕЛИЗЕ ===
  // Версия вашего приложения для отслеживания регрессий между релизами
  release: environment.version || '1.0.0',
  
  // Дистрибуция релиза (например, для разных сборок одной версии)
  // dist: 'canary',
  
  // === ОКРУЖЕНИЕ ===
  // Название окружения (production, staging, development и т.д.)
  environment: environment.production ? 'production' : 'development',
  
  // === ЭКСПЕРИМЕНТАЛЬНЫЕ ФУНКЦИИ ===
  // Включаем поддержку логов (Beta feature)
  _experiments: {
    enableLogs: true,
  },
  
  // === ИНТЕГРАЦИИ ===
  // Массив интеграций для расширения функциональности
  integrations: [
    // Включаем отслеживание сессий для Crash Free Rate
    Sentry.browserSessionIntegration(),
    
    // Экспериментальная функция: Browser Profiling
    // Захватывает профили производительности JavaScript в браузере
    Sentry.browserProfilingIntegration(),
    
    // Отслеживание производительности для Angular роутинга и HTTP запросов
    Sentry.browserTracingIntegration({
      // === ВРЕМЕННЫЕ НАСТРОЙКИ ===
      // Время ожидания для завершения idle span (мс)
      // idleTimeout: 1000, // по умолчанию: 1000
      
      // Максимальное время выполнения idle span (мс)
      // finalTimeout: 30000, // по умолчанию: 30000
      
      // Максимальное время для дочерних span (мс)
      // childSpanTimeout: 15000, // по умолчанию: 15000
      
      // === ИНСТРУМЕНТИРОВАНИЕ ===
      // Создавать span при загрузке страницы (важно для FCP, LCP, TTFB)
      instrumentPageLoad: true,
      
      // Создавать span при навигации (изменение history)
      instrumentNavigation: true,
      
      // === СВЯЗЫВАНИЕ ТРЕЙСОВ ===
      // Связывать текущий трейс с предыдущим
      // linkPreviousTrace: 'in-memory', // 'in-memory' | 'session-storage' | 'off'
      
      // Последовательное сэмплирование трейсов
      // consistentTraceSampling: false, // по умолчанию: false
      
      // === ПРОИЗВОДИТЕЛЬНОСТЬ ===
      // Захватывать Long Tasks
      enableLongTask: true, // по умолчанию: true
      
      // Захватывать Long Animation Frames
      // enableLongAnimationFrame: false, // по умолчанию: false
      
      // Захватывать INP (Interaction to Next Paint)
      enableInp: true, // по умолчанию: true
      
      // Захватывать Element Timing
      // enableElementTiming: true, // по умолчанию: true
      
      // === HTTP ТРЕКИНГ ===
      // Трейсить fetch запросы
      // traceFetch: true, // по умолчанию: true
      
      // Трейсить XHR запросы
      // traceXHR: true, // по умолчанию: true
      
      // Трекать производительность долгих потоков (SSE)
      // trackFetchStreamPerformance: false, // по умолчанию: false
      
      // Захватывать HTTP тайминги
      // enableHTTPTimings: true, // по умолчанию: true
      
      // === ФИЛЬТРАЦИЯ ===
      // Игнорировать resource spans по типу
      // ignoreResourceSpans: ['resource.img'], // по умолчанию: []
      
      // Игнорировать performance.mark/measure по имени
      // ignorePerformanceApiSpans: ['myMark', /^react-/], // по умолчанию: []
      
      // === ЭКСПЕРИМЕНТАЛЬНЫЕ ФУНКЦИИ ===
      _experiments: {
        // Включаем отслеживание взаимодействий для Web Vitals
        // но контролируем их через beforeStartSpan
        enableInteractions: true,
        
        // Создавать отдельные CLS spans
        // enableStandaloneClsSpans: false,
        
        // Создавать отдельные LCP spans
        // enableStandaloneLcpSpans: false,
      },
      
      // === КОЛБЭКИ ===
      // Модификация опций перед созданием span
      beforeStartSpan: (options) => {
        // Логирование для отладки (можно удалить в продакшене)
        if (!environment.production && options.op?.startsWith('ui.')) {
          console.log('[Sentry] Creating span:', options.name, options.op);
        }
        
        // Для взаимодействий (кликов) которые происходят после загрузки страницы
        if (options.op?.startsWith('ui.action') || options.op?.startsWith('ui.click')) {
          const activeSpan = Sentry.getActiveSpan();
          if (activeSpan) {
            const rootSpan = Sentry.getRootSpan(activeSpan);
            const rootOp = rootSpan ? (rootSpan as any).op : undefined;
            
            // Если мы все еще в контексте pageload/navigation
            if (rootOp === 'pageload' || rootOp === 'navigation') {
              // Проверяем, прошло ли достаточно времени после загрузки
              const startTime = (rootSpan as any).startTime;
              const currentTime = Date.now() / 1000; // Convert to seconds
              const timeSinceStart = currentTime - startTime;
              
              // Если прошло больше 3 секунд после загрузки, не присоединяем к pageload
              if (timeSinceStart > 3) {
                console.log('[Sentry] Preventing click attachment to pageload, time since start:', timeSinceStart);
                // Возвращаем options без изменений - span будет создан как дочерний
                // но наш createNewTrace все равно создаст независимую транзакцию
                return options;
              }
            }
          }
        }
        
        return options;
      },
      
      // Фильтр создания spans для запросов
      // shouldCreateSpanForRequest: (url) => {
      //   // Не создавать span для определенных URL
      //   return !url.includes('/health');
      // },
      
      // Обработка после создания span для запроса
      // onRequestSpanStart: (span, requestInfo) => {
      //   // Добавить дополнительные атрибуты к span
      //   span.setAttributes({
      //     'custom.header': requestInfo.headers?.['X-Custom-Header'],
      //   });
      // },
      
      // Помечать span как "cancelled" при уходе в фон
      // markBackgroundSpan: true, // по умолчанию: true
    }),
    
    // Запись сессий пользователей
    Sentry.replayIntegration({
      // === МАСКИРОВКА ДАННЫХ ===
      // Маскировать весь текст для приватности
      maskAllText: false, // В демо показываем текст
      
      // Маскировать все поля ввода
      maskAllInputs: false, // В демо показываем вводимые данные
      
      // Блокировать все медиа элементы (img, video, audio)
      blockAllMedia: false,
      
      // CSS селекторы для маскировки/разблокировки конкретных элементов
      // mask: ['.sensitive-data'],
      // unmask: ['.safe-data'],
      // block: ['.private-media'],
      // unblock: ['.public-media'],
      
      // === СЕТЕВЫЕ ЗАПРОСЫ ===
      // URL-ы для которых записывать детали запросов/ответов
      networkDetailAllowUrls: [/^\/api\//, /^https?:\/\/[^\/]+\/api\//],
      
      // Записывать тела запросов/ответов
      // networkCaptureBodies: true,
      
      // Дополнительные заголовки для записи
      // networkRequestHeaders: ['X-Custom-Header'],
      // networkResponseHeaders: ['X-Response-Header'],
      
      // === ПРОИЗВОДИТЕЛЬНОСТЬ REPLAY ===
      // Минимальная длительность replay в мс
      minReplayDuration: 5000,
      
      // Максимальная длительность replay в мс (по умолчанию 60 минут)
      maxReplayDuration: 60000, // Ограничить 1 минутой для демо
      
      // === ОБРАБОТКА ОШИБОК ===
      // Обработчик ошибок записи
      onError: (error) => console.error('Replay error:', error),
    }),
    
    // Виджет обратной связи от пользователей
    Sentry.feedbackIntegration({
      // Цветовая схема виджета
      colorScheme: 'system', // 'light' | 'dark' | 'system'
      
      // Автоинжект виджета в DOM
      autoInject: true,
      
      // Показывать имя/email поля
      showName: true,
      showEmail: true,
      
      // Обязательные поля
      isNameRequired: false,
      isEmailRequired: false,
      
      // Кастомизация текстов
      // buttonLabel: 'Сообщить о проблеме',
      // submitButtonLabel: 'Отправить',
      // successMessageText: 'Спасибо за обратную связь!',
    }),
    
    // Захват консольных сообщений
    Sentry.captureConsoleIntegration({
      levels: ['log', 'info', 'warn', 'error', 'debug', 'trace'], // Захватываем все уровни для демо
    }),
    
    // Контекстные строки вокруг ошибок
    // Sentry.contextLinesIntegration({
    //   frameContextLines: 7, // Количество строк контекста
    // }),
    
    // Отслеживание изменений в DOM (для дебага)
    // Sentry.breadcrumbsIntegration({
    //   console: true,
    //   dom: true,
    //   fetch: true,
    //   history: true,
    //   xhr: true,
    // }),
  ],
  
  // Отключить стандартные интеграции (если нужно)
  // defaultIntegrations: false,
  
  // === ОТПРАВКА ДАННЫХ ===
  // Отправлять персональные данные (IP, заголовки запросов и т.д.)
  sendDefaultPii: true,
  
  // Отправлять данные о клиенте (OS, браузер и т.д.)
  sendClientReports: true,
  
  // === СЭМПЛИРОВАНИЕ ===
  // Частота записи транзакций производительности (0-1, где 1 = 100%)
  tracesSampleRate: 1.0,
  
  // Частота записи сессий пользователей (0-1)
  replaysSessionSampleRate: 1.0, // 100% для демо
  
  // Частота записи сессий при ошибках (0-1)
  replaysOnErrorSampleRate: 1.0, // 100% при ошибках
  
  // Частота профилирования (требует tracesSampleRate > 0)
  profilesSampleRate: 1.0,
  
  // Кастомная функция сэмплирования транзакций
  // tracesSampler: (samplingContext) => {
  //   // Не трейсить health-check эндпоинты
  //   if (samplingContext.name === '/api/health') {
  //     return 0;
  //   }
  //   // 50% для остальных
  //   return 0.5;
  // },
  
  // === РАСПРОСТРАНЕНИЕ ТРЕЙСОВ ===
  // URL-паттерны для которых добавлять sentry-trace и baggage заголовки
  tracePropagationTargets: ['localhost', /^\/api\//, /^https?:\/\/[^\/]+\/api\//],
  
  // === ФИЛЬТРАЦИЯ ===
  // Игнорировать ошибки по паттерну
  // ignoreErrors: [
  //   'ResizeObserver loop limit exceeded',
  //   /extension\//i,
  //   /^Non-Error promise rejection captured/,
  // ],
  
  // Игнорировать транзакции по имени
  // ignoreTransactions: ['/api/health', '/ping'],
  
  // Запретить URL-ы (не отправлять ошибки с этих доменов)
  // denyUrls: ['chrome-extension://', 'safari-extension://'],
  
  // Разрешить только эти URL-ы
  // allowUrls: ['https://yourapp.com/', 'https://api.yourapp.com/'],
  
  // === ХУКИ И ОБРАБОТЧИКИ ===
  // Обработка события перед отправкой
  // beforeSend: (event, hint) => {
  //   // Фильтрация или модификация события
  //   if (event.exception) {
  //     // Можно вернуть null чтобы не отправлять событие
  //   }
  //   return event;
  // },
  
  // Обработка транзакции перед отправкой
  // beforeSendTransaction: (transaction, hint) => {
  //   // Модификация или фильтрация транзакций
  //   return transaction;
  // },
  
  // Обработка breadcrumb перед добавлением
  // beforeBreadcrumb: (breadcrumb, hint) => {
  //   // Фильтрация хлебных крошек
  //   if (breadcrumb.category === 'console') {
  //     return null; // Не добавлять
  //   }
  //   return breadcrumb;
  // },
  
  // === ТРАНСПОРТ И ТУННЕЛИРОВАНИЕ ===
  // URL для туннелирования событий (обход блокировщиков)
  // tunnel: '/api/tunnel',
  
  // Кастомные опции транспорта
  // transportOptions: {
  //   // Заголовки для запросов к Sentry
  //   headers: {
  //     'X-Custom-Header': 'value',
  //   },
  //   // Таймаут отправки (мс)
  //   fetchOptions: {
  //     timeout: 30000,
  //   },
  // },
  
  // === ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ ===
  // Режим отладки (логирование в консоль)
  debug: !environment.production,
  
  // Максимальное количество breadcrumbs
  // maxBreadcrumbs: 100,
  
  // Максимальная глубина объектов при сериализации
  // normalizeDepth: 10,
  
  // Максимальная длина строк значений
  // maxValueLength: 1000,
  
  // Прикреплять стек вызовов к сообщениям
  // attachStacktrace: true,
  
  // Автоматическое управление сессиями (удалено в v9, используйте browserSessionIntegration)
  // autoSessionTracking: true,
  
  // Начальный scope
  // initialScope: {
  //   tags: { component: 'frontend' },
  //   user: { id: '123' },
  // },
  
  // === ИНТЕГРАЦИЯ С OPENTELEMETRY ===
  // Кастомные OpenTelemetry инструментации
  // openTelemetryInstrumentations: [
  //   // new CustomInstrumentation(),
  // ],
  
  // === РЕЖИМ ИЗОЛЯЦИИ ===
  // Включить клиент в изолированном режиме
  // enabled: true,
  
  // === БЕЗОПАСНОСТЬ ===
  // Отключить Native SDK (React Native, Electron)
  // enableNative: false,
  
  // Отключить автозахват ошибок
  // enableAutoCapture: true,
});

if (environment.production) {
  enableProdMode();
}

bootstrapApplication(AppComponent, appConfig)
  .catch(err => console.error(err));