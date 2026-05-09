# DUMPSTER

**DUMPSTER** is a high-end photo curation and sequencing platform designed to help creators build the perfect Instagram "dump." By combining aesthetic heuristics with advanced AI, Dumpster transforms a chaotic photo library into a curated narrative.

---

## 🚀 Executive Summary

In the era of the "photo dump," the challenge isn't taking photos—it's selecting and sequencing them. Dumpster uses a proprietary **Dump Formula** to score and arrange photos based on visual contrast, category mix, and narrative flow. Whether you're a professional creator or a casual user, Dumpster provides the tools to build carousels that feel intentional and high-end.

## ✨ Core Features

### 🧠 AI-Powered Curation
- **Intelligent Clustering**: Automatically groups photos from your library into suggested "dumps" using Apple Vision and custom clustering algorithms.
- **Automated Sequencing**: Uses the "Dump Formula" to arrange photos into a 7 or 12-slot carousel, ensuring a perfect mix of "hooks," "details," and "atmosphere."
- **Multi-Provider Captions**: Generates professional, on-brand captions using Anthropic Claude, OpenAI, and other LLM providers.

### 📱 Dual-Platform Architecture
- **Native iOS App**: A high-performance SwiftUI implementation leveraging SwiftData for local persistence and Apple Vision for on-device image analysis.
- **Web Application**: A modern React + Vite + TypeScript web app for rapid curation and cross-platform accessibility.

### 🛠 Professional Workflow
- **Vibe Check**: Real-time analysis of color temperature and category consistency across your dump.
- **Undo/Redo System**: A robust, snapshot-based state management system for non-destructive editing.
- **Custom Heuristics**: Fine-tune the arrangement logic to match your personal aesthetic.

## 🛠 Tech Stack

### iOS (Native)
- **Framework**: SwiftUI
- **Persistence**: SwiftData
- **AI/ML**: Apple Vision (Image Classification & Clustering)
- **Networking**: Multi-provider LLM integration (OpenAI, Claude, Gemini, etc.)

### Web
- **Framework**: React 19 + Vite
- **State Management**: Zustand
- **Styling**: Modern CSS with native-feel design tokens
- **Drag & Drop**: @dnd-kit

## 🗺 Roadmap

The project is currently undergoing a **Native Conversion**, migrating the core web UI into a 100% native SwiftUI experience to leverage deeper iOS integrations and improved performance. See `docs/NATIVE_CONVERSION_SPEC.pdf` for the full technical specification.

---

*Built for the next generation of digital storytellers.*
