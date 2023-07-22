import debby/postgres

let db = openDatabase("localhost", "", "testuser", "test", "test")

include common_test

db.close()
