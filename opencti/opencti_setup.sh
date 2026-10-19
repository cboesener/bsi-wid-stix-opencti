#!/bin/sh
# Richtet im aktuellen Ordner eine frische, schlanke OpenCTI-Instanz ein:
# Plattform, Worker, STIX-Import-Connector sowie Redis, Elasticsearch, MinIO, RabbitMQ.
# Grundlage: offizielle docker-compose.yml von OpenCTI-Platform/docker, reduziert auf das
# fuer die Evaluation Noetige (ohne XTM One, ohne Export-Connectoren).
#
# Aufruf:  sh opencti_setup.sh     danach:  docker compose up -d
set -e

if [ -f .env ]; then
  echo "In diesem Ordner gibt es schon eine .env. Abbruch, damit keine Zugangsdaten ueberschrieben werden."
  exit 1
fi

uuid() { uuidgen | tr 'A-Z' 'a-z'; }
ADMIN_PASSWORD=$(openssl rand -hex 12)

# --- RabbitMQ: groessere Nachrichten erlauben (wichtig fuer Bundles mit >10.000 Objekten)
cat > rabbitmq.conf <<'EOF'
max_message_size = 536870912
consumer_timeout = 86400000
EOF

# --- Zugangsdaten und Kennungen (werden hier zufaellig erzeugt)
cat > .env <<EOF
MINIO_ROOT_USER=opencti
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
RABBITMQ_DEFAULT_USER=opencti
RABBITMQ_DEFAULT_PASS=$(openssl rand -hex 16)
ELASTIC_MEMORY_SIZE=2G

OPENCTI_HOST=localhost
OPENCTI_PORT=8080
OPENCTI_EXTERNAL_SCHEME=http
OPENCTI_ADMIN_EMAIL=admin@example.com
OPENCTI_ADMIN_PASSWORD=${ADMIN_PASSWORD}
OPENCTI_ADMIN_TOKEN=$(uuid)
OPENCTI_HEALTHCHECK_ACCESS_KEY=$(openssl rand -hex 16)
OPENCTI_ENCRYPTION_KEY=$(openssl rand -base64 32)

CONNECTOR_IMPORT_FILE_STIX_ID=$(uuid)
EOF

# --- Dienste
cat > docker-compose.yml <<'EOF'
services:
  redis:
    image: redis:8.10.1
    restart: always
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.19.21
    volumes:
      - esdata:/usr/share/elasticsearch/data
    environment:
      - discovery.type=single-node
      - xpack.ml.enabled=false
      - xpack.security.enabled=false
      - thread_pool.search.queue_size=5000
      - logger.org.elasticsearch.discovery="ERROR"
      - "ES_JAVA_OPTS=-Xms${ELASTIC_MEMORY_SIZE} -Xmx${ELASTIC_MEMORY_SIZE}"
    restart: always
    ulimits:
      memlock: { soft: -1, hard: -1 }
      nofile: { soft: 65536, hard: 65536 }
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://elasticsearch:9200/_cluster/health?wait_for_status=yellow >/dev/null || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 50

  minio:
    image: minio/minio:RELEASE.2025-04-22T22-12-26Z
    volumes:
      - s3data:/data
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server /data
    restart: always
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 10s
      timeout: 5s
      retries: 3

  rabbitmq:
    image: rabbitmq:4.3-management
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}
      - RABBITMQ_NODENAME=rabbit01@localhost
    volumes:
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro
      - amqpdata:/var/lib/rabbitmq
    restart: always
    healthcheck:
      test: rabbitmq-diagnostics -q ping
      interval: 30s
      timeout: 30s
      retries: 3

  opencti:
    image: opencti/platform:latest
    environment:
      - NODE_OPTIONS=--max-old-space-size=4096
      - APP__PORT=8080
      - APP__BASE_URL=${OPENCTI_EXTERNAL_SCHEME}://${OPENCTI_HOST}:${OPENCTI_PORT}
      - APP__ADMIN__EMAIL=${OPENCTI_ADMIN_EMAIL}
      - APP__ADMIN__PASSWORD=${OPENCTI_ADMIN_PASSWORD}
      - APP__ADMIN__TOKEN=${OPENCTI_ADMIN_TOKEN}
      - APP__ENCRYPTION_KEY=${OPENCTI_ENCRYPTION_KEY}
      - APP__HEALTH_ACCESS_KEY=${OPENCTI_HEALTHCHECK_ACCESS_KEY}
      - REDIS__HOSTNAME=redis
      - REDIS__PORT=6379
      - ELASTICSEARCH__URL=http://elasticsearch:9200
      - ELASTICSEARCH__NUMBER_OF_REPLICAS=0
      - MINIO__ENDPOINT=minio
      - MINIO__PORT=9000
      - MINIO__USE_SSL=false
      - MINIO__ACCESS_KEY=${MINIO_ROOT_USER}
      - MINIO__SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - RABBITMQ__HOSTNAME=rabbitmq
      - RABBITMQ__PORT=5672
      - RABBITMQ__PORT_MANAGEMENT=15672
      - RABBITMQ__MANAGEMENT_SSL=false
      - RABBITMQ__USERNAME=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ__PASSWORD=${RABBITMQ_DEFAULT_PASS}
      - PROVIDERS__LOCAL__STRATEGY=LocalStrategy
    ports:
      - "${OPENCTI_PORT}:8080"
    depends_on:
      redis: { condition: service_healthy }
      elasticsearch: { condition: service_healthy }
      minio: { condition: service_healthy }
      rabbitmq: { condition: service_healthy }
    restart: always
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://opencti:8080/health?health_access_key=${OPENCTI_HEALTHCHECK_ACCESS_KEY}"]
      interval: 10s
      timeout: 5s
      retries: 20

  worker:
    image: opencti/worker:latest
    environment:
      - OPENCTI_URL=http://opencti:8080
      - OPENCTI_TOKEN=${OPENCTI_ADMIN_TOKEN}
    depends_on:
      opencti: { condition: service_healthy }
    deploy:
      mode: replicated
      replicas: 2
    restart: always

  connector-import-file-stix:
    image: opencti/connector-import-file-stix:latest
    environment:
      - OPENCTI_URL=http://opencti:8080
      - OPENCTI_TOKEN=${OPENCTI_ADMIN_TOKEN}
      - CONNECTOR_ID=${CONNECTOR_IMPORT_FILE_STIX_ID}
      - CONNECTOR_TYPE=INTERNAL_IMPORT_FILE
      - CONNECTOR_NAME=ImportFileStix
      - CONNECTOR_VALIDATE_BEFORE_IMPORT=false   # direkt importieren, ohne manuelle Freigabe
      - CONNECTOR_SCOPE=application/json,text/xml
      - CONNECTOR_AUTO=true                      # hochgeladene Dateien automatisch importieren
    restart: always
    depends_on:
      opencti: { condition: service_healthy }

volumes:
  esdata:
  s3data:
  redisdata:
  amqpdata:
EOF

echo ""
echo "Fertig. Dateien: docker-compose.yml, .env, rabbitmq.conf"
echo "Starten mit:   docker compose up -d"
echo "Login unter http://localhost:8080"
echo "  E-Mail:   admin@example.com"
echo "  Passwort: ${ADMIN_PASSWORD}   (steht auch in .env)"
