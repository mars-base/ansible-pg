#!/usr/bin/env python3
"""
FerretDB (MongoDB wire protocol proxy) test script
Tests FerretDB core features: collection create, document insert, query, delete
"""

import sys
import argparse

try:
    from pymongo import MongoClient
    from pymongo.errors import ConnectionFailure, OperationFailure
except ImportError:
    print("pymongo not installed. Install with: pip install pymongo")
    sys.exit(1)


def run_tests(host, port, user, password, schema):
    uri = f"mongodb://{user}:{password}@{host}:{port}/{schema}"
    print(f"Connecting to {host}:{port} ...")

    client = MongoClient(uri, serverSelectionTimeoutMS=5000)
    try:
        client.admin.command("ping")
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

    passed = 0
    failed = 0

    def check(desc, ok):
        nonlocal passed, failed
        status = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1
        print(f"  [{status}] {desc}")

    collection_name = "products"
    db = client["testdb"]
    col = db[collection_name]

    # 0. cleanup
    col.drop()

    # 1. insert documents
    print(f"\n1. Insert documents")
    docs = [
        {"name": "iPhone 15 Pro", "category": "phone", "price": 8999, "stock": 100},
        {"name": "Galaxy S24", "category": "phone", "price": 6999, "stock": 200},
        {"name": "MacBook Pro M3", "category": "laptop", "price": 14999, "stock": 50},
    ]
    result = col.insert_many(docs)
    check(f"insert {len(docs)} documents", len(result.inserted_ids) == len(docs))

    # 2. find all
    print(f"\n2. Find all documents")
    all_docs = list(col.find())
    check(f"found {len(all_docs)} documents", len(all_docs) == len(docs))
    for doc in all_docs:
        print(f"    - {doc['name']}: price={doc['price']}")

    # 3. count
    print(f"\n3. Count documents")
    count = col.count_documents({})
    check(f"count = {count}", count == len(docs))

    # 4. find with filter
    print(f"\n4. Find with filter (category='phone')")
    phones = list(col.find({"category": "phone"}))
    check(f"found {len(phones)} phones", len(phones) == 2)
    for doc in phones:
        print(f"    - {doc['name']}")

    # 5. update
    print(f"\n5. Update document")
    update_result = col.update_one(
        {"name": "iPhone 15 Pro"},
        {"$set": {"price": 7999, "stock": 150}}
    )
    check(f"matched {update_result.matched_count}, modified {update_result.modified_count}",
          update_result.modified_count == 1)

    updated = col.find_one({"name": "iPhone 15 Pro"})
    check(f"price updated to {updated['price']}", updated["price"] == 7999)

    # 6. delete one
    print(f"\n6. Delete one document")
    del_result = col.delete_one({"name": "Galaxy S24"})
    check(f"deleted {del_result.deleted_count} document", del_result.deleted_count == 1)
    remaining = col.count_documents({})
    check(f"remaining count = {remaining}", remaining == 2)

    # 7. cleanup
    print(f"\n7. Drop collection")
    col.drop()
    final_count = col.count_documents({})
    check(f"collection dropped (count={final_count})", final_count == 0)

    client.close()

    total = passed + failed
    print(f"\n{'='*40}")
    print(f"Tests: {passed}/{total} passed, {failed} failed")
    print(f"{'='*40}")
    return failed == 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FerretDB test")
    parser.add_argument("-H", "--host", default="127.0.0.1", help="FerretDB host")
    parser.add_argument("-p", "--port", type=int, default=27017, help="MongoDB port")
    parser.add_argument("-U", "--user", default="dba", help="Username")
    parser.add_argument("-W", "--password", default="", help="Password")
    parser.add_argument("-s", "--schema", default="postgres", help="MongoDB database name (maps to PG schema)")
    args = parser.parse_args()

    try:
        ok = run_tests(args.host, args.port, args.user, args.password, args.schema)
    except Exception as e:
        print(f"\nTest error: {e}")
        sys.exit(1)

    sys.exit(0 if ok else 1)
