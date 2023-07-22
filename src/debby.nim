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

when defined(nimdoc):
  # Used to generate docs.
  import debby/common
  import debby/sqlite
  import debby/postgres
  import debby/mysql
else:
  {.error: "Import debby/sqlite, debby/postgres, or debby/mysql".}
