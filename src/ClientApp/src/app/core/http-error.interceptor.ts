import { Injectable } from '@angular/core';
import { HttpEvent, HttpInterceptor, HttpHandler, HttpRequest, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class HttpErrorInterceptor implements HttpInterceptor {
    intercept(req: HttpRequest<any>, next: HttpHandler): Observable<HttpEvent<any>> {
        const requestId = uuidv4();
        const cloned = req.clone({ setHeaders: { 'X-Request-Id': requestId } });
        return next.handle(cloned).pipe(
            catchError((error: HttpErrorResponse) => {
                console.error('HTTP Error', { requestId, status: error.status, message: error.message });
                return throwError(() => error);
            })
        );
    }
}
