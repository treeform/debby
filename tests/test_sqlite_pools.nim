import debby/pools, debby/sqlite

block:
  let pool = newPool()
  for i in 0 ..< 10:
    pool.add sqlite.openDatabase(
      path = "tests/test.db"
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
  pool.add sqlite.openDatabase(
    path = "tests/test.db"
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
