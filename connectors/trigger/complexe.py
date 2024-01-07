from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
import re

def main():
    try:
        # Connect to the MongoDB instance running on localhost
        client = MongoClient('mongodb://localhost:27017/?replicaSet=rs0')
        db = client['test']  # Using the 'test' database
        transaction_col = db['transaction']
        rtransaction_col = db['rtransaction']
        ptransaction_col = db['ptransaction']

        with transaction_col.watch() as stream:
            for change in stream:
                if change['operationType'] in ['insert', 'update']:
                    doc = change['fullDocument']
                    # Check if document only has '_id' and 'message'
                    if set(doc.keys()) == {'_id', 'message'}:
                        message = doc.get('message')
                        # Ensure message is not 'set' or matches 'backup\d'
                        if message != 'set' and not re.match(r'backup\d', message):
                            parts = message.split(':', 1)
                            new_doc = {
                                'transactionId': parts[0],
                                'transaction': parts[1] if len(parts) > 1 else ''
                            }
                            if parts[0] != 'del':
                                rtransaction_col.insert_one(new_doc)
                    else:
                        # Handle documents with more attributes
                        if 'payload' in doc and 'after' in doc['payload']:
                            new_doc = doc['payload']['after']
                            ptransaction_col.insert_one(new_doc)

    except ConnectionFailure as e:
        print(f"Connection failed: {e}")

if __name__ == "__main__":
    main()
