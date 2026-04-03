import { useEffect, useRef, useState } from 'react';
import { useStore } from '../store';
import CropEditor from './CropEditor';

export default function Lightbox() {
  const { lightboxPhotoId, photos, setLightbox, cropPhoto } = useStore();
  const photo = photos.find(p => p.id === lightboxPhotoId);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [cropOpen, setCropOpen] = useState(false);

  useEffect(() => {
    if (!lightboxPhotoId) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') setLightbox(null); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [lightboxPhotoId, setLightbox]);

  if (!photo) return null;

  const isVideo = /\.(mp4|mov|webm)$/i.test(photo.filename);

  return (
    <div
      className="lightbox-overlay"
      onClick={() => setLightbox(null)}
      style={{
        position: 'fixed', inset: 0, zIndex: 1000,
        background: 'rgba(0,0,0,0.92)', backdropFilter: 'blur(12px)',
        WebkitBackdropFilter: 'blur(12px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
    >
      <div
        className="lightbox-img"
        onClick={e => e.stopPropagation()}
        style={{
          position: 'relative', maxWidth: '92vw', maxHeight: '92vh',
          borderRadius: 12, overflow: 'hidden',
          boxShadow: '0 32px 80px rgba(0,0,0,0.8)',
        }}
      >
        {isVideo ? (
          <video
            ref={videoRef}
            src={photo.url}
            controls
            autoPlay
            style={{ maxWidth: '88vw', maxHeight: '88vh', display: 'block' }}
          />
        ) : (
          <img
            src={photo.url}
            alt={photo.filename}
            style={{ maxWidth: '88vw', maxHeight: '88vh', display: 'block', objectFit: 'contain' }}
          />
        )}

        {/* Info strip */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          background: 'linear-gradient(transparent, rgba(0,0,0,0.8))',
          padding: '24px 16px 14px',
          display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end',
        }}>
          <div>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.5)', fontWeight: 700, letterSpacing: '0.1em', marginBottom: 2 }}>
              {photo.category}
            </p>
            <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.7)' }}>{photo.filename}</p>
            {photo.labels.length > 0 && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 6 }}>
                {photo.labels.map(l => (
                  <span key={l} style={{
                    fontSize: 9, background: 'rgba(200,169,110,0.2)', color: 'var(--gold)',
                    padding: '2px 6px', borderRadius: 3, fontWeight: 600, letterSpacing: '0.08em',
                  }}>{l}</span>
                ))}
              </div>
            )}
          </div>
          {photo.isHuji && (
            <span style={{
              fontSize: 9, background: 'rgba(190,60,45,0.9)', color: '#fff',
              padding: '3px 7px', borderRadius: 4, fontWeight: 700, letterSpacing: '0.1em',
            }}>HUJI</span>
          )}
        </div>

        {/* Crop button */}
        {!isVideo && (
          <button
            onClick={(e) => { e.stopPropagation(); setCropOpen(true); }}
            style={{
              position: 'absolute', top: 10, right: 45,
              width: 30, height: 30, borderRadius: '50%',
              background: 'rgba(0,0,0,0.6)', border: 'none',
              color: 'var(--gold)', fontSize: 14, cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
            title="Crop photo"
          >📐</button>
        )}

        {/* Close button */}
        <button
          onClick={() => setLightbox(null)}
          style={{
            position: 'absolute', top: 10, right: 10,
            width: 30, height: 30, borderRadius: '50%',
            background: 'rgba(0,0,0,0.6)', border: 'none',
            color: '#fff', fontSize: 16, cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >×</button>

        {/* Crop Editor */}
        {cropOpen && (
          <CropEditor
            photoUrl={photo.url}
            onCropComplete={(croppedBlob) => {
              cropPhoto(photo.id, croppedBlob);
              setCropOpen(false);
            }}
            onCancel={() => setCropOpen(false)}
          />
        )}
      </div>
    </div>
  );
}
