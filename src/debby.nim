##
## **Debby - Database ORM layer.**
##
## Import the database engine you want to use:
##
## .. code-block:: nim
##     import debby/sqlite
##     import debby/postgres
##     import debby/mysql
##
## If you are going to use debby in mummy you want connection pools:
##
## .. code-block:: nim
##     import debby/pools

when defined(nimdoc):
  # Used to generate docs.
  import debby/common
  import debby/sqlite
  import debby/postgres
  import debby/mysql
  import debby/pools
else:
  {.error: "Import debby/sqlite, debby/postgres, or debby/mysql".}
