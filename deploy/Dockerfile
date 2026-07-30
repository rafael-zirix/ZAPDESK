# Imagem de runtime do zapdesk. O binário já vem cross-compilado para arm64
# (build no Mac); aqui só empacotamos com migrações e o build web.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 app
WORKDIR /app
COPY zapdesk-api /app/zapdesk-api
COPY migrations /app/migrations
COPY web /app/web
RUN mkdir -p /app/media && chown app /app/media
ENV WEB_DIR=/app/web
ENV MEDIA_DIR=/app/media
USER app
EXPOSE 8080
ENTRYPOINT ["/app/zapdesk-api"]
