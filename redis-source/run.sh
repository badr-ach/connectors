#!/bin/bash

set -e
(
if lsof -Pi :6379 -sTCP:LISTEN -t >/dev/null ; then
    echo "Please terminate the local redis-server on 6379"
    exit 1
fi
)

echo "Building the MongoDB Kafka Connector"
(
cd ./mongo-sink-connector
./gradlew clean createConfluentArchive
echo -e "Unzipping the confluent archive plugin....\n"
unzip -d ./build/confluent ./build/confluent/*.zip
find ./build/confluent -maxdepth 1 -type d ! -wholename "./build/confluent" -exec mv {} ./build/confluent/kafka-connect-mongodb \;
)

echo "Building the Redis Kafka Connector"
(
cd ./mongo-sink-connector/redis-kafka
docker build -t jaredpetersen/kafka-connect-redis:latest .
)

echo "Starting docker"
docker compose up -d

function clean_up {
    echo -e "\n\nSHUTTING DOWN\n\n"
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/datagen-pageviews || true
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/redis-sink || true
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/redis-source || true
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/redis-keys-source || true
    curl --output /dev/null -X DELETE http://localhost:8084/connectors/mongo-redis-sink-connector || true
    docker compose down
    if [ -z "$1" ]
    then
      echo -e "Bye!\n"
    else
      echo -e "$1"
    fi
}

sleep 5
echo -ne "\n\nWaiting for the systems to be ready.."
function test_systems_available {
  COUNTER=0
  until $(curl --output /dev/null --silent --head --fail http://localhost:$1); do
      printf '.'
      sleep 10
      (( COUNTER+=1 ))
      if [[ $COUNTER -gt 50 ]]; then
        MSG="\nWARNING: Could not reach configured kafka system on http://localhost:$1 \nNote: This script requires curl.\n"

          if [[ "$OSTYPE" == "darwin"* ]]; then
            MSG+="\nIf using OSX please try reconfiguring Docker and increasing RAM and CPU. Then restart and try again.\n\n"
          fi

        echo -e "$MSG"
        clean_up "$MSG"
        exit 1
      fi
  done
}

test_systems_available 8082
test_systems_available 8083
test_systems_available 8084
test_systems_available 8085

trap clean_up EXIT

echo -e "\nKafka Topics:"
curl -X GET "http://localhost:8082/topics" -w "\n"

echo -e "\nKafka Connectors:"
curl -X GET "http://localhost:8083/connectors/" -w "\n"
curl -X GET "http://localhost:8084/connectors/" -w "\n"

sleep 5
echo -e "\n Adding Postgres Kafka Source Connector for the 'public.transaction' table:"
curl -X POST -H "Content-Type: application/json" --data '
{
  "name": "transaction-db-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "plugin.name": "pgoutput",
    "tasks.max": "1",
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "postgresuser",
    "database.password": "postgrespass",
    "database.dbname": "transaction-db",
    "database.server.name": "postgres",
    "table.include.list": "public.transaction",
    "database.history.kafka.bootstrap.servers": "broker:29092",
    "database.history.kafka.topic": "schema-changes.transaction",
    "topic.prefix": "postgres",
    "topic.creation.enable": "true",
    "topic.creation.default.replication.factor": "1",
    "topic.creation.default.partitions": "1",
    "topic.creation.default.cleanup.policy": "delete",
    "topic.creation.default.retention.ms": "604800000"
  }
}
' http://localhost:8085/connectors -w "\n"

sleep 2
echo -e "\nAdding Keys Source Connector for keys 'mykey:*':"
curl -X POST -H "Content-Type: application/json" --data '
{   "name": "redis-keys-source",
            "config": {
            "connector.class": "io.github.jaredpetersen.kafkaconnectredis.source.RedisSourceConnector",
            "tasks.max": "1",
            "topic": "redis.events",
            "redis.uri": "redis://redis:6379",
            "redis.channels": "__key*__:*",
            "redis.channels.pattern.enabled": true
        }
}' http://localhost:8083/connectors -w "\n"

sleep 2

echo -e "\nAdding MongoDB Kafka Sink Connector for the 'test.redis-transaction' collection:"
curl -X POST -H "Content-Type: application/json" --data '
{  "name": "mongo-redis-sink-connector",
   "config": {
     "connector.class":"com.mongodb.kafka.connect.MongoSinkConnector",
     "tasks.max":"1",
     "topics":"redis.events",
     "connection.uri":"mongodb://mongo1:27017",
     "database":"test",
     "collection":"transaction",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter"
   }
}' http://localhost:8084/connectors -w "\n"

sleep 2

echo -e "\nAdding MongoDB Kafka Sink Connector for the 'test.transaction' collection:"
curl -X POST -H "Content-Type: application/json" --data '
{  "name": "mongo-postgres-sink-connector",
   "config": {
     "connector.class":"com.mongodb.kafka.connect.MongoSinkConnector",
     "tasks.max":"1",
     "topics":"postgres.public.transaction",
     "connection.uri":"mongodb://mongo1:27017",
     "database":"test",
     "collection":"transaction",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
   }
}' http://localhost:8084/connectors -w "\n"

echo -e "\nKafka Connectors: \n"
curl -X GET "http://localhost:8083/connectors/" -w "\n"
curl -X GET "http://localhost:8084/connectors/" -w "\n"

echo "Enabling keyspace notifications on Redis database:"
docker compose exec redis /opt/redis-stack/bin/redis-cli config set notify-keyspace-events KEA

sleep 2
echo -e '''


==============================================================================================================
Examine the topics in the Kafka UI: http://localhost:9021 or http://localhost:8000/
  - The `pageviews` topic should have the generated page views.
  - The `mystream` topic should contain the Redis stream messages.
The `pageviews` stream in Redis should contain the sunk page views: redis-cli xlen pageviews

Examine the Redis database:
  - In your shell run: docker compose exec redis /opt/redis-stack/bin/redis-cli
  - List some RedisJSON keys: SCAN 0 TYPE ReJSON-RL
  - Show the JSON value of a given key: JSON.GET pageviews:971
==============================================================================================================

Use <ctrl>-c to quit'''

read -r -d '' _ </dev/tty
