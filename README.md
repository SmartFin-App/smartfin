# SmartFin Monorepo 🐾

Personal financial management copilot for Thailand, featuring frictionless PromptPay bank slip scanning and an autonomous Multi-Agent RAG system.

## Repository Structure

```
smartfin/
├── smartfin-flutter/       # Mobile client (Flutter / Dart)
│   ├── lib/                # App code (Dashboard, Scanner, AI Coach, BLoC)
│   ├── android/            # Android native project & permissions
│   ├── ios/                # iOS native project & permissions
│   └── pubspec.yaml        # Flutter dependencies
│
├── smartfin-backend/       # Backend API (Golang / Gin)
│   ├── cmd/api/            # Server entrypoint
│   ├── internal/agents/    # Multi-Agent RAG (Orchestrator, Retrieval, Action, Research)
│   ├── internal/handlers/  # HTTP endpoints (Coach, Scanner, Transactions)
│   └── go.mod              # Go dependencies
│
└── API postman/            # Postman API collections
```

## Quick Start

### 1. Backend (Go)
```bash
cd smartfin-backend
go run cmd/api/main.go
```

### 2. Frontend (Flutter)
```bash
cd smartfin-flutter
flutter pub get
flutter run
```
