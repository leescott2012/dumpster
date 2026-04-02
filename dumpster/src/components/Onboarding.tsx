import { useState, useEffect } from 'react';

interface OnboardingProps {
  onComplete: () => void;
}

export const Onboarding = ({ onComplete }: OnboardingProps) => {
  const [currentStep, setCurrentStep] = useState(0);
  const steps = [
    {
      title: "Build Your Dumps",
      description: "Organize your photos into curated collections following the carousel formula for maximum impact.",
      icon: "📱",
      gradient: "linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%)"
    },
    {
      title: "Drag to Reorder",
      description: "Click and drag photos to perfect your sequence. Order matters—it tells a story.",
      icon: "🎯",
      gradient: "linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%)"
    },
    {
      title: "Pick from the Pool",
      description: "Choose photos from your pool to fill each slot. The formula guides you to the perfect picks.",
      icon: "🏊",
      gradient: "linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%)"
    },
    {
      title: "Check the Vibe",
      description: "Verify color consistency across your dump. Click 'Check Vibe' to ensure everything flows together.",
      icon: "✨",
      gradient: "linear-gradient(135deg, #1a1a1a 0%, #2a2a2a 100%)"
    }
  ];

  const step = steps[currentStep];
  const progress = ((currentStep + 1) / steps.length) * 100;

  const handleNext = () => {
    if (currentStep < steps.length - 1) {
      setCurrentStep(currentStep + 1);
    } else {
      handleComplete();
    }
  };

  const handleSkip = () => {
    handleComplete();
  };

  const handleComplete = () => {
    localStorage.setItem('onboardingCompleted', 'true');
    onComplete();
  };

  useEffect(() => {
    // Keyboard navigation
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') handleNext();
      if (e.key === 'ArrowLeft' && currentStep > 0) setCurrentStep(currentStep - 1);
      if (e.key === 'Escape') handleSkip();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [currentStep]);

  return (
    <div style={{
      position: 'fixed',
      inset: 0,
      background: step.gradient,
      zIndex: 9999,
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'center',
      alignItems: 'center',
      padding: '32px',
      color: '#fff'
    }}>
      {/* Background decoration */}
      <div style={{
        position: 'absolute',
        inset: 0,
        overflow: 'hidden',
        pointerEvents: 'none'
      }}>
        {[...Array(6)].map((_, i) => (
          <div
            key={i}
            style={{
              position: 'absolute',
              width: '200px',
              height: '200px',
              borderRadius: '50%',
              background: `rgba(200, 169, 110, ${0.05 + i * 0.02})`,
              left: `${-100 + i * 25}%`,
              top: `${-100 + i * 20}%`,
              animation: `float ${8 + i * 2}s ease-in-out infinite`,
            }}
          />
        ))}
      </div>

      {/* Content container */}
      <div style={{
        position: 'relative',
        zIndex: 1,
        maxWidth: '500px',
        textAlign: 'center',
        animation: 'fadeIn 0.5s ease-out'
      }}>
        {/* Icon */}
        <div style={{
          fontSize: '120px',
          marginBottom: '32px',
          animation: 'bounce 2s ease-in-out infinite'
        }}>
          {step.icon}
        </div>

        {/* Title */}
        <h1 style={{
          fontSize: '48px',
          fontWeight: 800,
          marginBottom: '16px',
          letterSpacing: '-0.02em',
          color: 'var(--gold)',
          textShadow: '0 2px 8px rgba(0,0,0,0.3)'
        }}>
          {step.title}
        </h1>

        {/* Description */}
        <p style={{
          fontSize: '18px',
          color: 'var(--text3)',
          lineHeight: 1.6,
          marginBottom: '48px',
          fontWeight: 400
        }}>
          {step.description}
        </p>

        {/* Progress bar */}
        <div style={{
          width: '100%',
          height: '4px',
          background: 'rgba(255,255,255,0.1)',
          borderRadius: '2px',
          marginBottom: '32px',
          overflow: 'hidden'
        }}>
          <div style={{
            height: '100%',
            background: 'var(--gold)',
            width: `${progress}%`,
            transition: 'width 0.3s ease-out'
          }} />
        </div>

        {/* Step indicators */}
        <div style={{
          display: 'flex',
          gap: '8px',
          justifyContent: 'center',
          marginBottom: '48px'
        }}>
          {steps.map((_, i) => (
            <button
              key={i}
              onClick={() => setCurrentStep(i)}
              style={{
                width: '12px',
                height: '12px',
                borderRadius: '50%',
                border: 'none',
                background: i === currentStep ? 'var(--gold)' : 'rgba(255,255,255,0.2)',
                cursor: 'pointer',
                transition: 'all 0.3s ease'
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLButtonElement).style.transform = 'scale(1.2)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLButtonElement).style.transform = 'scale(1)';
              }}
            />
          ))}
        </div>

        {/* Buttons */}
        <div style={{
          display: 'flex',
          gap: '12px',
          justifyContent: 'center',
          flexWrap: 'wrap'
        }}>
          <button
            onClick={handleSkip}
            style={{
              padding: '12px 32px',
              borderRadius: '8px',
              border: '1px solid var(--border2)',
              background: 'transparent',
              color: 'var(--text2)',
              fontSize: '16px',
              fontWeight: 600,
              cursor: 'pointer',
              transition: 'all 0.2s',
              minWidth: '120px'
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--gold)';
              (e.currentTarget as HTMLButtonElement).style.color = 'var(--gold)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--border2)';
              (e.currentTarget as HTMLButtonElement).style.color = 'var(--text2)';
            }}
          >
            {currentStep === steps.length - 1 ? 'Done' : 'Skip'}
          </button>
          <button
            onClick={handleNext}
            style={{
              padding: '12px 32px',
              borderRadius: '8px',
              border: 'none',
              background: 'var(--gold)',
              color: '#000',
              fontSize: '16px',
              fontWeight: 600,
              cursor: 'pointer',
              transition: 'all 0.2s',
              minWidth: '120px'
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(-2px)';
              (e.currentTarget as HTMLButtonElement).style.boxShadow = '0 8px 16px rgba(200,169,110,0.3)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(0)';
              (e.currentTarget as HTMLButtonElement).style.boxShadow = 'none';
            }}
          >
            {currentStep === steps.length - 1 ? 'Let\'s Go' : 'Next'}
          </button>
        </div>

        {/* Keyboard hint */}
        <p style={{
          fontSize: '12px',
          color: 'rgba(255,255,255,0.4)',
          marginTop: '24px'
        }}>
          Use arrow keys to navigate • Press ESC to skip
        </p>
      </div>

      <style>{`
        @keyframes fadeIn {
          from {
            opacity: 0;
            transform: translateY(20px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }

        @keyframes bounce {
          0%, 100% {
            transform: translateY(0);
          }
          50% {
            transform: translateY(-20px);
          }
        }

        @keyframes float {
          0%, 100% {
            transform: translateY(0px) rotate(0deg);
          }
          50% {
            transform: translateY(30px) rotate(180deg);
          }
        }
      `}</style>
    </div>
  );
};
