FROM postgres:16-alpine

# Self-signed TLS certificate so client connections can be encrypted
# (Middle-level non-functional requirement: "connections use SSL/TLS where supported").
# Lab-grade only: self-signed, not CA-verified. In production, use a certificate
# issued by a trusted/internal CA and sslmode=verify-full on clients.
RUN apk add --no-cache openssl \
    && mkdir -p /etc/postgresql/certs \
    && openssl req -new -x509 -days 3650 -nodes \
         -subj "/CN=peex-postgres" \
         -newkey rsa:2048 \
         -keyout /etc/postgresql/certs/server.key \
         -out /etc/postgresql/certs/server.crt \
    && chown postgres:postgres /etc/postgresql/certs/server.key /etc/postgresql/certs/server.crt \
    && chmod 600 /etc/postgresql/certs/server.key \
    && chmod 644 /etc/postgresql/certs/server.crt

# Custom pg_hba.conf: only TLS ("hostssl") connections from localhost or the
# docker-compose bridge network are allowed; every other host is rejected.
# (Middle-level non-functional requirement: network access restricted via
# firewall/subnet rules — here enforced at the database layer.)
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
