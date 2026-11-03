# Container image for Google Cloud Run (or any container host).
# Cloud Run sets $PORT, which cmd/main.go already listens on.

# Build with the Go version go.mod asks for.
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Static binary, so the runtime image needs no C library.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd

# Minimal runtime: CA certificates for HTTPS to MongoDB Atlas and Gemini,
# no shell, running as a non-root user.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENTRYPOINT ["/server"]
