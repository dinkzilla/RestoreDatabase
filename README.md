# RestoreDatabase.sql

This script will restore sql database backups to newer versions of sql.

It will work with any database backuped up from a version of SQL 2012 or later and currently supports restoring to any version up to SQL 2016. The running version of SQL must be at the same as the backedup up version or newer.

Inputs:

@BakFile - the fully qualified path to the backup file (.bak)

@DatabaseName - the desired name of the new restored database 

Note: The @DatabaseName does not need to match original name. Also, this is simply a name not a file path, as the default sql file path setting is detected automatically by the script.

