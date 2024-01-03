#!/bin/bash

set -e
(
if lsof -Pi :27017 -sTCP:LISTEN -t >/dev/null ; then
    echo "Please terminate the local mongod on 27017"
    exit 1
fi
)

echo "Building the MongoDB Kafka Connector"
(
cd ..
./gradlew clean createConfluentArchive
echo -e "Unzipping the confluent archive plugin....\n"
unzip -d ./build/confluent ./build/confluent/*.zip
find ./build/confluent -maxdepth 1 -type d ! -wholename "./build/confluent" -exec mv {} ./build/confluent/kafka-connect-mongodb \;
)

echo "Building the Redis Kafka Connector"
(
cd ../redis-kafka
docker build -t jaredpetersen/kafka-connect-redis:latest .
)

echo "Starting docker ."
docker-compose up -d --build

function clean_up {
    echo -e "\n\nSHUTTING DOWN\n\n"
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/datagen-pageviews || true
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/mongo-sink || true
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/mongo-source || true
    docker-compose exec mongo1 /usr/bin/mongo --eval "db.dropDatabase()"
    docker-compose down
    if [ -z "$1" ]
    then
      echo -e "Bye!\n"
    else
      echo -e $1
    fi
}

sleep 5
echo -ne "\n\nWaiting for the systems to be ready.."
function test_systems_available {
  COUNTER=0
  until $(curl --output /dev/null --silent --head --fail http://localhost:$1); do
      printf '.'
      sleep 2
      let COUNTER+=1
      if [[ $COUNTER -gt 30 ]]; then
        MSG="\nWARNING: Could not reach configured kafka system on http://localhost:$1 \nNote: This script requires curl.\n"

          if [[ "$OSTYPE" == "darwin"* ]]; then
            MSG+="\nIf using OSX please try reconfiguring Docker and increasing RAM and CPU.\
                In Docker Desktop this can be done via the \"Resources\" tab in \"Preferences\". Then try again.\n\n"
          fi

        echo -e $MSG
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

# echo -e "\nCreating kafka topics for mysql connector:"
# docker-compose run --rm kafka kafka-topics --create --topic quickstart-avro-offsets --partitions 1 --replication-factor 1 --if-not-exists --zookeeper zookeeper:32181 --config cleanup.policy=compact
# docker-compose run --rm kafka kafka-topics --create --topic quickstart-avro-config --partitions 1 --replication-factor 1 --if-not-exists --zookeeper zookeeper:32181 --config cleanup.policy=compact
# docker-compose run --rm kafka kafka-topics --create --topic quickstart-avro-status --partitions 1 --replication-factor 1 --if-not-exists --zookeeper zookeeper:32181 --config cleanup.policy=compact
# sleep 5

echo -e "\nAdding datagen pageviews:"
curl -X POST -H "Content-Type: application/json" --data '
  { "name": "datagen-pageviews",
    "config": {
      "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
      "kafka.topic": "pageviews",
      "quickstart": "pageviews",
      "key.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter.schemas.enable": "false",
      "producer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor",
      "max.interval": 200,
      "iterations": 10000000,
      "tasks.max": "1"
}}' http://localhost:8083/connectors -w "\n"

sleep 5
echo -e "\n Adding Postgres Kafka Source Connector for the 'public.transaction' table:"
curl -X POST -H "Content-Type: application/json" -d @postgres-source-connector.json http://localhost:8084/connectors -w "\n"

# echo -e "\n Adding Mysql Kafka Source Connector for the 'public.transaction' table:"
# # curl -X POST -H "Content-Type: application/json" -d @mysql-source-connector.json http://localhost:8084/connectors -w "\n"
# curl -X POST -H "Content-Type: application/json" --data '
#   { "name": "quickstart-jdbc-source", 
#     "config": { 
#       "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector", 
#       "tasks.max": 1, 
#       "connection.url": "jdbc:mysql://mysql:3306/connect_test", 
#       "connection.user": "root", 
#       "connection.password": "test", 
#       "mode": "incrementing", 
#       "incrementing.column.name": "id", 
#       "timestamp.column.name": "modified", 
#       "topic.prefix": "quickstart-jdbc-", 
#       "poll.interval.ms": 1000 
#     }}' http://localhost:28083/connectors -w "\n"

sleep 2
echo -e "\nAdding Keys Source Connector for keys 'mykey:*':"
curl -X POST -H "Content-Type: application/json" -d @redis-source-connector.json http://localhost:8085/connectors -w "\n"

sleep 2
echo -e "\nAdding Keys Source Connector for keys 'mykey:*':"
curl -X POST -H "Content-Type: application/json" -d @redis-source-connector-2.json http://localhost:8085/connectors -w "\n"

sleep 2
echo -e "\nAdding MongoDB Kafka Sink Connector for the 'test.transaction' collection:"
curl -X POST -H "Content-Type: application/json" -d @mongo-sink-connector.json http://localhost:8083/connectors -w "\n"

echo -e "\nAdding MongoDB Kafka Sink Connector for the 'test.redis-transaction' collection:"
curl -X POST -H "Content-Type: application/json" -d @mongo-sink-connector-2.json http://localhost:8083/connectors -w "\n"



sleep 2
echo -e "\nKafka Connectors: \n"
curl -X GET "http://localhost:8083/connectors/" -w "\n"
curl -X GET "http://localhost:8084/connectors/" -w "\n"
curl -X GET "http://localhost:8085/connectors/" -w "\n"

echo "Looking at data in 'db.pageviews':"
docker-compose exec mongo1 /usr/bin/mongo --eval 'db.pageviews.find()'


echo -e '''

==============================================================================================================
Examine the topics in the Kafka UI: http://localhost:9021 or http://localhost:8000/
  - The `pageviews` topic should have the generated page views.
  - The `mongo.test.pageviews` topic should contain the change events.
  - The `test.pageviews` collection in MongoDB should contain the sinked page views.

Examine the collections:
  - In your shell run: docker-compose exec mongo1 /usr/bin/mongo
==============================================================================================================

Use <ctrl>-c to quit'''

read -r -d '' _ </dev/tty
