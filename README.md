# RestoreDatabase.sql

This script will restore sql database backups to newer versions of sql. It will work with any database backuped up from a version of SQL 2012 or later and currently supports restoring to any version up to SQL 2016. The running version of SQL must be at the same as the backedup up version or newer. The bakup's local name and physical database name must also be the same,  

This functionality is handeled by Sql Server Management Studio automatically when restoring manually, but this script allows it to be executed during automated scripts and tasks. For example, it can be called from a grunt task to set up testing databases for developers from a standard backup file despite using different SQL environments.

The script detects the InstanceDefaultDataPath and builds an appropriate path to MOVE the database(s) to once restored. This requires the script to first restore HeaderOnly and FileListOnly. The results sets returned by HeaderOnly and FileListOnly grow with each new version of SQL Server, so the script also contains logic to adjust for this. Currently, it supports 2012, 2014, and 2016. If you are on a newer version and are getting errors claiming that "Column name or number of supplied values does not match table definition" and that RESTORE HEADERONLY or FILELISTONLY "terminated abnormally", you need to add logic to modify the @HeaderSql and @FileListSql variables to account for your version's results sets.


## Inputs:

* $DatabaseName - the logical name you wish to assign to the restored database, which does not need to match the old database.

* $BakFile - the file path to the backup file that you wish to restore from

Note: The @DatabaseName does not need to match original name. Also, this is simply a name not a file path, as the default sql file path setting is detected automatically by the script.


## Naming Convention:
The expected logical naming convention in the backup is \[OriginalDatabaseName\]\[Suffix\] and it will create database with logical names in the format \[$DatabaseName\]\[Suffix\]. For information on logical vs database name, how to look them up, and best practices on keeping them in sync, [click here.](http://pnsoftwarestudies.blogspot.com/2013/08/DifferenceBetweenDatabaseNameLogicalNameAndPhysicalNameOfADatabaseInSQLServer.html)

* OriginalDatabaseName - This is retrieved from the backup file header.

* Suffix - Anything beyond the length of the OriginalDatabaseName, which may include naming convention suffixes such as "_log" and file extensions such as ".ldf".


For example, the Database Name in automation.bak is "automation" so the files will get named as noted below with a $DatabaseName of "input":

* automation.mdf => input.mdf

* automation_log.ldf => input_log.ldf
