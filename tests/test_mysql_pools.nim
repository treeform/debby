import debby/pools, debby/mysql

block:
  let pool = newPool()
  for i in 0 ..< 5:
    pool.add openDatabase(
      host = "127.0.0.1",
      user = "root",
      database = "test_db",
      password = "hunter2",
      port = 3306
    )

  pool.withDb:
    doAssert db.query("select ?", 1) == @[@["1"]]

  proc threadFunc() =
    for i in 0 ..< 100:
      pool.withDb:
        doAssert db.query("select ?", i) == @[@[$i]]

  var threads: array[0 .. 9, Thread[void]]
  for i in 0..high(threads):
    createThread(threads[i], threadFunc)

  joinThreads(threads)

  pool.close()

block:
  let pool = newPool()
  pool.add openDatabase(
    host = "127.0.0.1",
    user = "root",
    database = "test_db",
    password = "hunter2",
    port = 3306
  )

  type Counter = ref object
    id: int
    number: int

  pool.withDb:
    db.dropTableIfExists(Counter)
    db.createTable(Counter)
    var counter = Counter()
    db.insert(counter)

  const numTimes = 20

  proc threadFunc() =
    for i in 0 ..< numTimes:
      pool.withDb:
        let counter = db.get(Counter, 1)
        counter.number += 1
        db.update(counter)

  var threads: array[0 .. 2, Thread[void]]
  for i in 0..high(threads):
    createThread(threads[i], threadFunc)

  joinThreads(threads)

  pool.withDb:
    let counter = db.get(Counter, 1)
    doAssert counter.number == threads.len * numTimes

  pool.close()
