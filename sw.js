// ============================================================
// Service Worker mínimo del Nuestro Espacio (app de pareja).
// Necesario para mostrar notificaciones del sistema en Android
// (Chrome móvil no permite notificaciones sin service worker).
// ============================================================
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// Al tocar la notificación: enfoca la app si está abierta, o la abre
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((ventanas) => ventanas.length ? ventanas[0].focus() : self.clients.openWindow('./'))
  );
});
