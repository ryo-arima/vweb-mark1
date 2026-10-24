FROM thevlang/vlang:alpine-dev AS builder

RUN apk add --no-cache postgresql-dev

WORKDIR /src
COPY . .
RUN mkdir -p /out
RUN v -prod -o /out/service-b-back ./cmd/server

FROM alpine:3.21

RUN apk add --no-cache postgresql-libs

WORKDIR /app
COPY --from=builder /out/service-b-back /app/service-b-back
EXPOSE 8000
ENTRYPOINT ["/app/service-b-back"]
