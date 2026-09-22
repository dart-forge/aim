/// MySQL driver for the Aim ORM framework.
library;

export 'src/connection.dart' show MySqlConnectionSettings, MySqlSslMode;
export 'src/exceptions.dart';
export 'src/mysql_database.dart'
    show
        MySqlDatabase,
        MySqlQueryable,
        MySqlTransaction,
        MySqlTransactionEndedByDdl;

export 'package:aim_database/aim_database.dart'
    show PoolOptions, PoolStats, PoolTimeoutException;
