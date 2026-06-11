FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/api \
    ./cmd/api

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S onlineprorab \
    && adduser -S -G onlineprorab -h /app onlineprorab \
    && mkdir -p /app /data/uploads \
    && chown -R onlineprorab:onlineprorab /app /data

WORKDIR /app
COPY --from=build --chown=onlineprorab:onlineprorab /out/api /app/api

ENV HTTP_ADDR=:8080
ENV UPLOAD_DIR=/data/uploads

USER onlineprorab

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1

ENTRYPOINT ["/app/api"]
