# SmartFin: Automatic Expense Tracking with Thai E-Slip Recognition and an AI Financial Coach

**สมาร์ทฟิน: ระบบบันทึกค่าใช้จ่ายอัตโนมัติด้วยการอ่านสลิปอิเล็กทรอนิกส์และผู้ช่วยทางการเงินอัจฉริยะ**

SmartFin is the capstone project **CS66-BU77** for the CSC498–CSC499 Capstone Project course in Computer Science at the School of Information Technology (SIT), King Mongkut's University of Technology Thonburi (KMUTT).

🔗 Project page: <https://seniorproject.sit.kmutt.ac.th/showproject/CS66-BU77>

## About

SmartFin is a mobile app for Thai users that tracks spending. It records expenses from Thai mobile-banking e-slips (PromptPay, K PLUS, SCB EASY, Krungthai NEXT, BBL) and from paper receipts. Its AI Coach answers questions about the user's own spending in Thai or English, and a bill tracker reminds the user before payments are due.

- **E-slip scanning:** Gemini Vision reads the slip, including Thai script and Buddhist-era dates, and the user confirms the result before it is saved.
- **AI Coach:** an agentic-RAG loop that uses Gemini function calling to look up the user's own data in MongoDB before it answers.
- **Subscriptions & bills:** entered by hand, with reminders sent as local notifications on the device.

## Team

| Name | Student ID |
| --- | --- |
| Thaw Zin Moe Myint | 66130500824 |
| Ant Bone Kyaw | 66130500802 |
| Hnin Ei Ei Aung | 66130500808 |

**Advisor:** Dr. Debajyoti Pal

## Tech Stack

- **Mobile client:** Flutter / Dart, Google ML Kit, Firebase Auth with Google Sign-In
- **Backend API:** Go with Fiber v2, deployed with Docker on Google Cloud Run
- **AI:** Gemini Vision for slip extraction, Gemini function calling for the agentic-RAG coach
- **Database:** MongoDB Atlas

## Repository Structure

```
smartfin/
├── smartfin-flutter/       # Mobile client (Flutter / Dart)
│   ├── lib/                # App code (features: dashboard, scanner, AI Coach, bills)
│   ├── android/            # Android native project & permissions
│   ├── ios/                # iOS native project & permissions
│   └── pubspec.yaml        # Flutter dependencies
│
├── smartfin-backend/       # Backend API (Go / Fiber v2)
│   ├── cmd/main.go         # Server entrypoint
│   ├── cmd/eval/           # AI Coach answer-quality evaluation
│   ├── internal/agents/    # Agentic-RAG coach (orchestrator and tools)
│   ├── internal/handlers/  # HTTP endpoints (coach, scanner, transactions, subscriptions)
│   ├── Dockerfile          # Container image for Cloud Run
│   └── deploy.sh           # Build and deploy to Cloud Run
│
├── smartfin-docs/          # Capstone documents (proposal, report, test spec, poster)
└── API postman/            # Postman API collections
```

## Quick Start

### 1. Backend (Go)

```bash
cd smartfin-backend
go run cmd/main.go          # serves on $PORT (default 3000)
```

### 2. Frontend (Flutter)

```bash
cd smartfin-flutter
flutter pub get
flutter run --dart-define=API_BASE_URL=<backend URL>
```

Without `API_BASE_URL`, the app falls back to the emulator/simulator loopback address for a local backend. Real phones and release builds must pass it.

See [`smartfin-backend/CLAUDE.md`](smartfin-backend/CLAUDE.md) and [`smartfin-flutter/CLAUDE.md`](smartfin-flutter/CLAUDE.md) for environment variables, tests and per-target run flags.
