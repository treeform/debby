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

block:
  let pool = newPool()
  pool.add sqlite.openDatabase(
    path = "tests/test.db"
  )

  # Test with basic object
  type Auto = ref object
    id: int
    make: string
    model: string
    year: int

  var vintageSportsCars = @[
    Auto(make: "Chevrolet", model: "Camaro Z28", year: 1970),
    Auto(make: "Porsche", model: "911 Carrera RS", year: 1973),
    Auto(make: "Lamborghini", model: "Countach", year: 1974),
    Auto(make: "Ferrari", model: "308 GTS", year: 1977),
    Auto(make: "Aston Martin", model: "V8 Vantage", year: 1977),
    Auto(make: "Datsun", model: "280ZX", year: 1980),
    Auto(make: "Ferrari", model: "Testarossa", year: 1984),
    Auto(make: "BMW", model: "M3", year: 1986),
    Auto(make: "Mazda", model: "RX-7", year: 1993),
    Auto(make: "Toyota", model: "Supra", year: 1998)
  ]

  pool.dropTableIfExists(Auto)
  pool.checkTable(Auto)
  pool.insert(vintageSportsCars)
  pool.update(vintageSportsCars)
  pool.upsert(vintageSportsCars)
  pool.delete(vintageSportsCars)

  let cars = pool.filter(Auto)
  doAssert cars.len == 0

  var sportsCar = Auto(make: "Jeep", model: "Wangler Sahara", year: 1993)
  pool.insert(sportsCar)
  pool.update(sportsCar)
  pool.upsert(sportsCar)
  pool.delete(sportsCar)

  let cars2 = pool.filter(Auto, it.year > 1990)
  doAssert cars2.len == 0

  let cars3 = pool.query(Auto, "SELECT * FROM auto")
  doAssert cars3.len == 0

  pool.close()
