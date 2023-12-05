// To enter docker container called mongo and list all databases and collections
docker exec -it mongo mongo
show dbs
use test
show collections
db.test.find();
