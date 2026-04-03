import { useRef, useEffect, useState, useCallback } from 'react';

interface CropEditorProps {
  photoUrl: string;
  onCropComplete: (croppedBlob: Blob) => void;
  onCancel: () => void;
}

interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export default function CropEditor({ photoUrl, onCropComplete, onCancel }: CropEditorProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const overlayRef = useRef<HTMLDivElement>(null);

  const [crop, setCrop] = useState<CropRect>({ x: 0, y: 0, width: 300, height: 300 });
  const [imgDim, setImgDim] = useState({ width: 0, height: 0 });
  const [dragging, setDragging] = useState<'move' | 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | null>(null);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });

  // Load image and set initial crop
  useEffect(() => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const canvas = canvasRef.current;
      if (canvas) {
        const container = overlayRef.current?.parentElement;
        if (!container) return;

        const maxWidth = container.clientWidth - 100;
        const maxHeight = container.clientHeight - 200;

        let displayWidth = img.width;
        let displayHeight = img.height;

        if (displayWidth > maxWidth) {
          displayHeight = (maxWidth / displayWidth) * displayHeight;
          displayWidth = maxWidth;
        }
        if (displayHeight > maxHeight) {
          displayWidth = (maxHeight / displayHeight) * displayWidth;
          displayHeight = maxHeight;
        }

        canvas.width = displayWidth;
        canvas.height = displayHeight;
        setImgDim({ width: displayWidth, height: displayHeight });

        // Draw initial image
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(img, 0, 0, displayWidth, displayHeight);
        }

        // Set initial crop to center 60% of image
        const initialCrop = {
          x: displayWidth * 0.2,
          y: displayHeight * 0.2,
          width: displayWidth * 0.6,
          height: displayHeight * 0.6,
        };
        setCrop(initialCrop);
      }
    };
    img.src = photoUrl;
  }, [photoUrl]);

  // Draw crop overlay
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || imgDim.width === 0) return;

    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      // Draw full image with darkened area
      ctx.drawImage(img, 0, 0, imgDim.width, imgDim.height);
      ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
      ctx.fillRect(0, 0, imgDim.width, imgDim.height);

      // Clear crop area
      ctx.clearRect(crop.x, crop.y, crop.width, crop.height);
      ctx.drawImage(
        img,
        crop.x,
        crop.y,
        crop.width,
        crop.height,
        crop.x,
        crop.y,
        crop.width,
        crop.height
      );

      // Draw crop border
      ctx.strokeStyle = 'var(--gold)';
      ctx.lineWidth = 2;
      ctx.strokeRect(crop.x, crop.y, crop.width, crop.height);

      // Draw handles
      const handles = [
        { x: crop.x, y: crop.y, cursor: 'nw-resize' }, // nw
        { x: crop.x + crop.width / 2, y: crop.y, cursor: 'n-resize' }, // n
        { x: crop.x + crop.width, y: crop.y, cursor: 'ne-resize' }, // ne
        { x: crop.x + crop.width, y: crop.y + crop.height / 2, cursor: 'e-resize' }, // e
        { x: crop.x + crop.width, y: crop.y + crop.height, cursor: 'se-resize' }, // se
        { x: crop.x + crop.width / 2, y: crop.y + crop.height, cursor: 's-resize' }, // s
        { x: crop.x, y: crop.y + crop.height, cursor: 'sw-resize' }, // sw
        { x: crop.x, y: crop.y + crop.height / 2, cursor: 'w-resize' }, // w
      ];

      handles.forEach((handle, idx) => {
        ctx.fillStyle = 'var(--gold)';
        ctx.fillRect(handle.x - 5, handle.y - 5, 10, 10);
        ctx.strokeStyle = '#fff';
        ctx.lineWidth = 1;
        ctx.strokeRect(handle.x - 5, handle.y - 5, 10, 10);
      });
    };
    img.src = photoUrl;
  }, [crop, photoUrl, imgDim]);

  const getHandleAtPos = (x: number, y: number): string | null => {
    const threshold = 15;
    const handles: Record<string, [number, number]> = {
      nw: [crop.x, crop.y],
      n: [crop.x + crop.width / 2, crop.y],
      ne: [crop.x + crop.width, crop.y],
      e: [crop.x + crop.width, crop.y + crop.height / 2],
      se: [crop.x + crop.width, crop.y + crop.height],
      s: [crop.x + crop.width / 2, crop.y + crop.height],
      sw: [crop.x, crop.y + crop.height],
      w: [crop.x, crop.y + crop.height / 2],
    };

    for (const [key, [hx, hy]] of Object.entries(handles)) {
      if (Math.abs(x - hx) < threshold && Math.abs(y - hy) < threshold) {
        return key;
      }
    }

    // Check if inside crop rect (for move)
    if (x > crop.x && x < crop.x + crop.width && y > crop.y && y < crop.y + crop.height) {
      return 'move';
    }

    return null;
  };

  const handleMouseDown = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    const handle = getHandleAtPos(x, y);
    if (handle) {
      setDragging(handle as any);
      setDragStart({ x, y });
    }
  }, [crop]);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    if (!dragging) {
      const handle = getHandleAtPos(x, y);
      canvas.style.cursor = {
        nw: 'nw-resize',
        n: 'n-resize',
        ne: 'ne-resize',
        e: 'e-resize',
        se: 'se-resize',
        s: 's-resize',
        sw: 'sw-resize',
        w: 'w-resize',
        move: 'grab',
      }[handle || ''] || 'default';
      return;
    }

    const dx = x - dragStart.x;
    const dy = y - dragStart.y;

    const newCrop = { ...crop };
    const minSize = 50;

    switch (dragging) {
      case 'nw':
        newCrop.x = Math.max(0, crop.x + dx);
        newCrop.y = Math.max(0, crop.y + dy);
        newCrop.width = crop.width - dx;
        newCrop.height = crop.height - dy;
        break;
      case 'n':
        newCrop.y = Math.max(0, crop.y + dy);
        newCrop.height = crop.height - dy;
        break;
      case 'ne':
        newCrop.y = Math.max(0, crop.y + dy);
        newCrop.width = Math.min(imgDim.width - crop.x, crop.width + dx);
        newCrop.height = crop.height - dy;
        break;
      case 'e':
        newCrop.width = Math.min(imgDim.width - crop.x, crop.width + dx);
        break;
      case 'se':
        newCrop.width = Math.min(imgDim.width - crop.x, crop.width + dx);
        newCrop.height = Math.min(imgDim.height - crop.y, crop.height + dy);
        break;
      case 's':
        newCrop.height = Math.min(imgDim.height - crop.y, crop.height + dy);
        break;
      case 'sw':
        newCrop.x = Math.max(0, crop.x + dx);
        newCrop.width = crop.width - dx;
        newCrop.height = Math.min(imgDim.height - crop.y, crop.height + dy);
        break;
      case 'w':
        newCrop.x = Math.max(0, crop.x + dx);
        newCrop.width = crop.width - dx;
        break;
      case 'move':
        newCrop.x = Math.max(0, Math.min(imgDim.width - crop.width, crop.x + dx));
        newCrop.y = Math.max(0, Math.min(imgDim.height - crop.height, crop.y + dy));
        break;
    }

    if (newCrop.width >= minSize && newCrop.height >= minSize) {
      setCrop(newCrop);
      setDragStart({ x, y });
    }
  }, [dragging, dragStart, crop, imgDim]);

  const handleMouseUp = () => {
    setDragging(null);
  };

  const handleApplyCrop = async () => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      // Create a new canvas for the cropped image
      const cropCanvas = document.createElement('canvas');
      const ctx = cropCanvas.getContext('2d');
      if (!ctx) return;

      // Scale coordinates back to original image dimensions
      const scaleX = img.width / imgDim.width;
      const scaleY = img.height / imgDim.height;

      cropCanvas.width = crop.width * scaleX;
      cropCanvas.height = crop.height * scaleY;

      ctx.drawImage(
        img,
        crop.x * scaleX,
        crop.y * scaleY,
        crop.width * scaleX,
        crop.height * scaleY,
        0,
        0,
        crop.width * scaleX,
        crop.height * scaleY
      );

      cropCanvas.toBlob((blob) => {
        if (blob) {
          onCropComplete(blob);
        }
      }, 'image/jpeg', 0.95);
    };
    img.src = photoUrl;
  };

  return (
    <div
      ref={overlayRef}
      className="crop-editor-overlay"
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        background: 'rgba(0, 0, 0, 0.92)',
        backdropFilter: 'blur(8px)',
        WebkitBackdropFilter: 'blur(8px)',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
        gap: 20,
        padding: 20,
      }}
      onClick={(e) => e.currentTarget === e.target && onCancel()}
    >
      <div style={{ color: 'var(--text)', fontSize: 12, fontWeight: 600, letterSpacing: '0.1em', textTransform: 'uppercase' }}>
        Drag handles to crop • ESC to cancel
      </div>

      <canvas
        ref={canvasRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
        style={{
          maxWidth: '100%',
          maxHeight: 'calc(100% - 120px)',
          cursor: 'default',
          display: 'block',
        }}
      />

      <div style={{ display: 'flex', gap: 12 }}>
        <button
          onClick={onCancel}
          style={{
            padding: '8px 16px',
            borderRadius: 6,
            border: '1px solid var(--border2)',
            background: 'var(--bg2)',
            color: 'var(--text)',
            cursor: 'pointer',
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: '0.06em',
            transition: 'all 0.15s',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--gold)';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--gold)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--border2)';
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--text)';
          }}
        >
          Cancel
        </button>
        <button
          onClick={handleApplyCrop}
          style={{
            padding: '8px 16px',
            borderRadius: 6,
            border: '1px solid var(--gold)',
            background: 'rgba(200, 169, 110, 0.15)',
            color: 'var(--gold)',
            cursor: 'pointer',
            fontSize: 12,
            fontWeight: 600,
            letterSpacing: '0.06em',
            transition: 'all 0.15s',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(200, 169, 110, 0.25)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = 'rgba(200, 169, 110, 0.15)';
          }}
        >
          Apply Crop
        </button>
      </div>
    </div>
  );
}
