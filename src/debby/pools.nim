when not defined(gcArc) and not defined(gcOrc):
  {.error: "Using --mm:arc or --mm:orc is required by Waterpark.".}

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

proc get*[T, V](
  pool: Pool,
  t: typedesc[T],
  id: V
): T =
  pool.withDb:
    return db.get(t, id)
