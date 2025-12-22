import { ErrorHandler, Injectable } from '@angular/core';
import * as Sentry from '@sentry/angular';

@Injectable()
export class SentryErrorHandler implements ErrorHandler {
  handleError(error: Error): void {
    // Log to console for debugging
    console.error('Angular ErrorHandler caught:', error);
    
    // Add custom context for Angular errors
    Sentry.withScope(scope => {
      scope.setTag('error_type', 'angular_error_handler');
      scope.setLevel('error');
      
      // Add more context to help without source maps
      scope.setContext('angular_error', {
        message: error.message,
        stack: error.stack,
        timestamp: new Date().toISOString(),
        // Add component/file context from error
        component: this.extractComponentFromError(error),
        line: this.extractLineFromError(error)
      });
      
      // Add breadcrumb with error location
      Sentry.addBreadcrumb({
        message: `Error in ${this.extractComponentFromError(error) || 'unknown component'}`,
        level: 'error',
        category: 'angular',
        data: {
          errorMessage: error.message
        }
      });
      
      // Capture the exception with Sentry
      Sentry.captureException(error);
    });
    
    // You can add custom error handling logic here
    // For example, show a user-friendly error message
  }
  
  private extractComponentFromError(error: Error): string | null {
    // Try to extract component name from stack trace
    const stackLines = error.stack?.split('\n') || [];
    for (const line of stackLines) {
      // Look for component references
      if (line.includes('Component') || line.includes('.component.')) {
        const match = line.match(/(\w+Component)/);
        if (match) return match[1];
      }
    }
    return null;
  }
  
  private extractLineFromError(error: Error): string | null {
    // Try to extract line number from stack
    const match = error.stack?.match(/:(\d+):\d+/);
    return match ? `Line ${match[1]}` : null;
  }
}