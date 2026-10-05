#ifndef PERFECT_SQLITE_SHIM_H
#define PERFECT_SQLITE_SHIM_H

// C wrappers for SQLite calls Swift can't make directly
// (sqlite3_db_config is variadic, so it isn't imported).

struct sqlite3;

// Turns SQLite's double-quoted string literal misfeature on (enable != 0) or
// off for both DML and DDL on `db`. Returns SQLITE_OK when both settings now
// hold `enable`, otherwise SQLITE_ERROR (e.g. SQLite older than 3.29, which
// has neither option and always accepts "..." as a fallback string literal).
int perfect_sqlite3_set_dqs(struct sqlite3 *db, int enable);

#endif
