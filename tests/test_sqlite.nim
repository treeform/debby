import debby/sqlite

let db = openDatabase("tests/test.db")

include common_test

db.close()
