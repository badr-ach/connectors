from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

def main():
    try:
        # Connect to the MongoDB instance running on localhost
        client = MongoClient('mongodb://localhost:27017/?replicaSet=rs0')
        db = client['test']  # Using the 'test' database
        transaction_col = db['transaction']
        rtransaction_col = db['rtransaction']

        with transaction_col.watch() as stream:
            for change in stream:
                if change['operationType'] in ['insert', 'update']:
                    # Extract only the '_id' and 'message' fields
                    new_doc = {
                        '_id': change['fullDocument']['_id'],
                        'message': change['fullDocument'].get('message')
                    }
                    # Insert the new document into 'rtransaction'
                    rtransaction_col.insert_one(new_doc)

    except ConnectionFailure as e:
        print(f"Connection failed: {e}")

if __name__ == "__main__":
    main()
