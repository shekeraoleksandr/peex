FROM mongo:7

# Self-signed TLS certificate so client connections can be encrypted
# (Middle-level non-functional requirement: TLS/SSL where supported).
# Lab-grade only: self-signed, not CA-verified.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/mongo/certs \
    && openssl req -new -x509 -days 3650 -nodes \
         -subj "/CN=peex-mongo" \
         -newkey rsa:2048 \
         -keyout /etc/mongo/certs/mongo.key \
         -out /etc/mongo/certs/mongo.crt \
    && cat /etc/mongo/certs/mongo.key /etc/mongo/certs/mongo.crt > /etc/mongo/certs/mongo.pem \
    && chown mongodb:mongodb /etc/mongo/certs/mongo.pem \
    && chmod 600 /etc/mongo/certs/mongo.pem
