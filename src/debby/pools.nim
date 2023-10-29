
when not defined(nimdoc):
  when not compileOption("threads"):
    {.error: "Using --threads:on is required with debby pools.".}
  when not defined(gcArc) and not defined(gcOrc):
    {.error: "Using --mm:arc or --mm:orc is required with debby pools.".}

import std/locks, std/random, common

type
  Pool* = ptr PoolObj

  PoolObj = object
    entries: seq[Db]
    lock: Lock
    cond: Cond
    r: Rand

proc newPool*(): Pool =
  ## Creates a new thread-safe pool.
  ## Pool starts empty, don't forget to .add() DB connections.
  result = cast[Pool](allocShared0(sizeof(PoolObj)))
  initLock(result.lock)
  initCond(result.cond)
  result.r = initRand(2023)

proc borrow*(pool: Pool): Db {.raises: [], gcsafe.} =
  ## Note: you should use withDb instead.
  ## Takes an entry from the pool. This call blocks until it can take
  ## an entry. After taking an entry remember to add it back to the pool
  ## when you're finished with it.
  {.gcsafe.}:
    acquire(pool.lock)
    while pool.entries.len == 0:
      wait(pool.cond, pool.lock)
    result = pool.entries.pop()
    release(pool.lock)

proc add*(pool: Pool, t: Db) {.raises: [], gcsafe.} =
  ## Add new or returns an entry to the pool.
  {.gcsafe.}:
    withLock pool.lock:
      pool.entries.add(t)
      pool.r.shuffle(pool.entries)
    signal(pool.cond)

template close*(pool: Pool) =
  ## Closes all entires and Deallocates the pool.
  withLock pool.lock:
    for db in pool.entries:
      try:
        db.close()
      except:
        discard
  deinitLock(pool.lock)
  deinitCond(pool.cond)
  `=destroy`(pool[])
  deallocShared(pool)

template withDb*(pool: Pool, body: untyped) =
  block:
    let db {.inject.} = pool.borrow()
    try:
      body
    finally:
      pool.add(db)

proc dropTable*[T](pool: Pool, t: typedesc[T]) =
  ## Removes tables, errors out if it does not exist.
  pool.withDb:
    db.dropTable(t)

proc dropTableIfExists*[T](pool: Pool, t: typedesc[T]) =
  ## Removes tables if it exists.
  pool.withDb:
    db.dropTableIfExists(t)

proc createTable*[T: ref object](pool: Pool, t: typedesc[T]) =
  ## Creates a table, errors out if it already exists.
  pool.withDb:
    db.createTable(t)

template checkTable*[T: ref object](pool: Pool, t: typedesc[T]) =
  ## Checks to see if table matches the object.
  ## And recommends to create whole table or alter it.
  pool.withDb:
    db.checkTable(t)

proc get*[T, V](pool: Pool, t: typedesc[T], id: V): T =
  ## Gets the object by id.
  pool.withDb:
    return db.get(t, id)

proc update*[T: ref object](pool: Pool, obj: T) =
  ## Updates the row that corresponds to the object in the database.
  ## Makes sure the obj.id is set.
  pool.withDb:
    db.update(obj)

template update*[T: ref object](pool: Pool, objs: seq[T]) =
  ## Updates a seq of objects into the database.
  pool.withDb:
    db.update(objs)

proc delete*[T: ref object](pool: Pool, obj: T) =
  ## Deletes the row that corresponds to the object from the data
  ## base. Makes sure the obj.id is set.
  pool.withDb:
    db.delete(obj)

template delete*[T: ref object](pool: Pool, objs: seq[T]) =
  ## Deletes a seq of objects from the database.
  pool.withDb:
    db.delete(objs)

template insert*[T: ref object](pool: Pool, obj: T) =
  ## Inserts the object into the database.
  ## Reads the ID of the inserted ref object back.
  pool.withDb:
    db.insert(obj)

template insert*[T: ref object](pool: Pool, objs: seq[T]) =
  ## Inserts a seq of objects into the database.
  pool.withDb:
    db.insert(objs)

template upsert*[T: ref object](pool: Pool, obj: T) =
  ## Either updates or inserts a ref object into the database.
  ## Will read the inserted id back.
  pool.withDb:
    db.upsert(obj)

template upsert*[T: ref object](pool: Pool, objs: seq[T]) =
  ## Either updates or inserts a seq of object into the database.
  ## Will read the inserted id back for each object.
  pool.withDb:
    db.upsert(objs)

template filter*[T: ref object](pool: Pool, t: typedesc[T], expression: untyped): untyped =
  ## Filters type's table with a Nim like filter expression.
  ## db.filter(Auto, it.year > 1990)
  ## db.filter(Auto, it.make == "Ferrari" or it.make == "Lamborghini")
  ## db.filter(Auto, it.year >= startYear and it.year < endYear)
  var tmp: seq[T]
  pool.withDb:
    tmp = db.filter(t, expression)
  tmp

proc filter*[T](pool: Pool, t: typedesc[T]): seq[T] =
  ## Filter without a filter clause just returns everything.
  pool.withDb:
    return db.filter(t)

template query*(pool: Pool, sql: string, args: varargs[string, `$`]): seq[Row] =
  ## Query returning plain results
  var data: seq[Row]
  pool.withDb:
    db.query(sql, args)
  data

template query*[T](pool: Pool, t: typedesc[T], sql: string, args: varargs[string, `$`]): seq[T] =
  ## Gets the object by id.
  var data: seq[T]
  pool.withDb:
    data = db.query(t, sql, args)
  data
