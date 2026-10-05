#include <sqlite3.h>
#include "PerfectSQLiteShim.h"

int perfect_sqlite3_set_dqs(struct sqlite3 *db, int enable) {
#if defined(SQLITE_DBCONFIG_DQS_DML) && defined(SQLITE_DBCONFIG_DQS_DDL)
	int dml = -1, ddl = -1;
	enable = enable ? 1 : 0;
	if (sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, enable, &dml) != SQLITE_OK
		|| sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, enable, &ddl) != SQLITE_OK
		|| dml != enable || ddl != enable) {
		return SQLITE_ERROR;
	}
	return SQLITE_OK;
#else
	(void)db; (void)enable;
	return SQLITE_ERROR;
#endif
}
