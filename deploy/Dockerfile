# Imagem de runtime do zapdesk. O binário já vem cross-compilado para arm64
# (build no Mac); aqui só empacotamos com migrações e o build web.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 app
WORKDIR /app
COPY zapdesk-api /app/zapdesk-api
COPY migrations /app/migrations
COPY web /app/web
ENV WEB_DIR=/app/web
USER app
EXPOSE 8080
ENTRYPOINT ["/app/zapdesk-api"]
