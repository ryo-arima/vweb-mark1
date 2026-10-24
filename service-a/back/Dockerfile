FROM thevlang/vlang:alpine-dev AS builder

RUN apk add --no-cache postgresql-dev

WORKDIR /src
COPY . .
RUN mkdir -p /out
RUN v -prod -o /out/service-a-back ./cmd/server

FROM alpine:3.21

RUN apk add --no-cache postgresql-libs

WORKDIR /app
COPY --from=builder /out/service-a-back /app/service-a-back
EXPOSE 8000
ENTRYPOINT ["/app/service-a-back"]
