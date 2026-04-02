import { useEffect, useState } from 'react';

export const InstallPrompt = () => {
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null);
  const [showPrompt, setShowPrompt] = useState(false);
  const [isIOS, setIsIOS] = useState(false);

  useEffect(() => {
    // Detect iOS
    const ua = window.navigator.userAgent;
    const isApple = /iPad|iPhone|iPod/.test(ua);
    setIsIOS(isApple && !window.matchMedia('(display-mode: standalone)').matches);

    // Listen for beforeinstallprompt event
    const handleBeforeInstallPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e);
      setShowPrompt(true);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    };
  }, []);

  const handleInstall = async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      if (outcome === 'accepted') {
        setShowPrompt(false);
      }
      setDeferredPrompt(null);
    }
  };

  const handleDismiss = () => {
    setShowPrompt(false);
  };

  // Don't show if already installed or on iOS (they have separate instructions)
  if (!showPrompt && !isIOS) {
    return null;
  }

  return (
    <div style={{
      position: 'fixed',
      bottom: 20,
      right: 20,
      backgroundColor: '#000',
      color: '#fff',
      padding: '16px 20px',
      borderRadius: '8px',
      maxWidth: '300px',
      boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
      zIndex: 9999,
      fontFamily: 'system-ui, -apple-system, sans-serif',
      fontSize: '14px',
      lineHeight: '1.5'
    }}>
      {isIOS ? (
        <>
          <div style={{ fontWeight: 'bold', marginBottom: '8px' }}>📱 Add to Home Screen</div>
          <div style={{ fontSize: '12px', marginBottom: '10px' }}>
            Tap <span style={{ fontWeight: 'bold' }}>Share</span> → <span style={{ fontWeight: 'bold' }}>Add to Home Screen</span>
          </div>
          <button
            onClick={handleDismiss}
            style={{
              background: '#fff',
              color: '#000',
              border: 'none',
              padding: '6px 12px',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '12px',
              fontWeight: 'bold'
            }}
          >
            Got it
          </button>
        </>
      ) : (
        <>
          <div style={{ fontWeight: 'bold', marginBottom: '8px' }}>📱 Install App</div>
          <div style={{ fontSize: '12px', marginBottom: '10px' }}>
            Save DUMPSTER to your home screen for quick access
          </div>
          <div style={{ display: 'flex', gap: '8px' }}>
            <button
              onClick={handleInstall}
              style={{
                background: '#4CAF50',
                color: '#fff',
                border: 'none',
                padding: '6px 12px',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '12px',
                fontWeight: 'bold'
              }}
            >
              Install
            </button>
            <button
              onClick={handleDismiss}
              style={{
                background: 'transparent',
                color: '#fff',
                border: '1px solid #fff',
                padding: '6px 12px',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '12px'
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
