# Kafka-Connectors

This repo contains a redis, mongo and postgres connectors configured to work with kafka and zookeeper on debian 11.

### Registering a connector
- Run `curl -X POST -H "Content-Type: application/json" -d @connector.json http://<kafka-connect-url>/connectors`

### Testing the connector
- Run `docker exec -it <postgres-db-container-name> bash` to access the postgres container
- Run `psql -U <postgresusername> -d <postgres-db>` to access the postgres database
- Perform any SQL Querys properly handled by the postgres connector 

OR

- Run `docker exec -it <redis-db-container-name> redis-cli` to access the postgres container
- Run any REDIS Queries which are properly handled by the redis connector

### Viewing the data
- Run `docker exec -it kafka-service bash` to access the kafka container
- Run `kafka-console-consumer --bootstrap-server kafka-service:9092 --topic <topicname> --from-beginning`