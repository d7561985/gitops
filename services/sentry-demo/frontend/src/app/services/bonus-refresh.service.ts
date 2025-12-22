import { Injectable } from '@angular/core';
import { Subject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class BonusRefreshService {
  private refreshSubject = new Subject<void>();
  
  // Observable that components can subscribe to
  refreshRequested$ = this.refreshSubject.asObservable();
  
  // Method to trigger refresh
  triggerRefresh(): void {
    this.refreshSubject.next();
  }
}