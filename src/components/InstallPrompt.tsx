import { useEffect, useState } from 'react';

export const InstallPrompt = () => {
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null);
  const [showPrompt, setShowPrompt] = useState(false);
  const [isIOS, setIsIOS] = useState(false);
  const [installed, setInstalled] = useState(false);

  useEffect(() => {
    // Don't show if already dismissed
    if (localStorage.getItem('installDismissed')) return;

    const ua = window.navigator.userAgent;
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches;
    if (isStandalone) return; // already installed

    const isApple = /iPad|iPhone|iPod/.test(ua);
    if (isApple) {
      setIsIOS(true);
      setShowPrompt(true);
      return;
    }

    const handleBeforeInstallPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e);
      setShowPrompt(true);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    return () => window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
  }, []);

  const handleInstall = async () => {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    setDeferredPrompt(null);
    if (outcome === 'accepted') {
      setInstalled(true);
      setTimeout(() => {
        setShowPrompt(false);
        localStorage.setItem('installDismissed', '1');
      }, 2000);
    }
  };

  const handleDismiss = () => {
    setShowPrompt(false);
    localStorage.setItem('installDismissed', '1');
  };

  if (!showPrompt) return null;

  return (
    <div style={{
      position: 'fixed',
      bottom: 24,
      left: '50%',
      transform: 'translateX(-50%)',
      width: 'calc(100% - 40px)',
      maxWidth: 340,
      background: 'var(--bg2)',
      border: '1px solid var(--border2)',
      borderRadius: 14,
      padding: '16px 18px',
      boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
      zIndex: 9999,
      fontFamily: 'var(--font)',
    }}>
      {installed ? (
        <p style={{ fontSize: 13, color: 'var(--gold)', fontWeight: 600, textAlign: 'center' }}>
          Added to Home Screen
        </p>
      ) : isIOS ? (
        <>
          <p style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)', marginBottom: 6 }}>
            Add to Home Screen
          </p>
          <p style={{ fontSize: 12, color: 'var(--text3)', lineHeight: 1.5, marginBottom: 14 }}>
            Tap <strong style={{ color: 'var(--text)' }}>Share</strong> at the bottom of Safari, then tap{' '}
            <strong style={{ color: 'var(--text)' }}>Add to Home Screen</strong>.
          </p>
          <button
            onClick={handleDismiss}
            style={{
              width: '100%', padding: '10px 0', borderRadius: 8,
              background: 'var(--gold-dim)', border: '1px solid rgba(200,169,110,0.3)',
              color: 'var(--gold)', fontSize: 13, fontWeight: 700,
              cursor: 'pointer', fontFamily: 'var(--font)',
            }}
          >
            Got it
          </button>
        </>
      ) : (
        <>
          <p style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)', marginBottom: 6 }}>
            Add to Home Screen
          </p>
          <p style={{ fontSize: 12, color: 'var(--text3)', lineHeight: 1.5, marginBottom: 14 }}>
            Install DUMPSTER for quick access — works offline too.
          </p>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={handleInstall}
              style={{
                flex: 1, padding: '10px 0', borderRadius: 8,
                background: 'var(--gold-dim)', border: '1px solid rgba(200,169,110,0.3)',
                color: 'var(--gold)', fontSize: 13, fontWeight: 700,
                cursor: 'pointer', fontFamily: 'var(--font)',
              }}
            >
              Install
            </button>
            <button
              onClick={handleDismiss}
              style={{
                padding: '10px 16px', borderRadius: 8,
                background: 'transparent', border: '1px solid var(--border2)',
                color: 'var(--text3)', fontSize: 13,
                cursor: 'pointer', fontFamily: 'var(--font)',
              }}
            >
              Later
            </button>
          </div>
        </>
      )}
    </div>
  );
};
