USE MASTER;

IF (exists (SELECT name from master.dbo.sysdatabases
WHERE ('[' + name + ']' = '$(DatabaseName)'
or name = '$(DatabaseName)')))
BEGIN
ALTER DATABASE [$(DatabaseName)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
END


DECLARE
      @BackupFile nvarchar(260) = '$(BakFile)',
      @NewDatabaseName sysname = '$(DatabaseName)',
      @DataFolder nvarchar(260),
      @LogFolder nvarchar(260),
	  @LogicalName nvarchar(128),
      @PhysicalName nvarchar(260),
      @PhysicalFolderName nvarchar(260),
      @PhysicalFileName nvarchar(260),
      @NewPhysicalName nvarchar(260),
      @NewLogicalName nvarchar(128),
      @OldDatabaseName nvarchar(128),
      @RestoreStatement nvarchar(MAX),
      @Command nvarchar(MAX),
      @ReturnCode int,
      @FileType char(1),
      @ServerName nvarchar(128),
      @BackupFinishDate datetime,
      @Message nvarchar(4000),
      @ChangeLogicalNamesSql nvarchar(MAX),
      @Error int,
      @ProductVersion nvarchar(128),
      @ProductVersionNumber tinyint,
	  @HeaderSql nvarchar(MAX),
	  @FileListSql nvarchar(MAX)

/*
The reason for all the extra logic in this file is to compensate for varying default sql file paths and for varying versions of sql.
We get the file names using HEADERONLY and FILELISTONLY and then build new paths and RESTORE using MOVE to save them to the new locations.
*/

--get default paths (Only works in SQL 2012 and onward.)
select @DataFolder = convert(varchar(260), serverproperty('InstanceDefaultDataPath')),
@LogFolder = convert(varchar(260), serverproperty('InstanceDefaultLogPath'))
SET NOCOUNT ON;

--add trailing backslash to folder names if not already specified
IF LEFT(REVERSE(@DataFolder), 1) <> '\' SET @DataFolder = @DataFolder + '\';
IF LEFT(REVERSE(@LogFolder), 1) <> '\' SET @LogFolder = @LogFolder + '\';

--get SQL version
SET @ProductVersion = CONVERT(NVARCHAR(128),SERVERPROPERTY('ProductVersion'))
SET @ProductVersionNumber = SUBSTRING(@ProductVersion, 1, (CHARINDEX('.', @ProductVersion) - 1));

IF object_id('dbo.tblBakHeader') IS NOT NULL DROP TABLE dbo.tblBakHeader
IF object_id('dbo.tblBakFileList') IS NOT NULL DROP TABLE dbo.tblBakFileList

--Common return values for HeaderOnly
SET @HeaderSql = 'create table dbo.tblBakHeader
	 (BackupName nvarchar(128),
      BackupDescription nvarchar(255),
	  BackupType smallint,
      ExpirationDate datetime,
      Compressed tinyint,
      Position smallint,
      DeviceType tinyint,
      UserName nvarchar(128),
      ServerName nvarchar(128),
      DatabaseName nvarchar(128),
      DatabaseVersion int,
      DatabaseCreationDate  datetime,
      BackupSize numeric(20,0),
      FirstLSN numeric(25,0),
      LastLSN numeric(25,0),
      CheckpointLSN  numeric(25,0),
      DatabaseBackupLSN  numeric(25,0),
      BackupStartDate  datetime,
      BackupFinishDate  datetime,
      SortOrder smallint,
      CodePage smallint,
      UnicodeLocaleId int,
      UnicodeComparisonStyle int,
      CompatibilityLevel  tinyint,
      SoftwareVendorId int,
      SoftwareVersionMajor int,
      SoftwareVersionMinor int,
      SoftwareVersionBuild int,
      MachineName nvarchar(128),
      Flags int,
      BindingID uniqueidentifier,
      RecoveryForkID uniqueidentifier,
      Collation nvarchar(128),
      FamilyGUID uniqueidentifier,
      HasBulkLoggedData bit,
      IsSnapshot bit,
      IsReadOnly bit,
      IsSingleUser bit,
      HasBackupChecksums bit,
      IsDamaged bit,
      BeginsLogChain bit,
      HasIncompleteMetaData bit,
      IsForceOffline bit,
      IsCopyOnly bit,
      FirstRecoveryForkID uniqueidentifier,
      ForkPointLSN decimal(25, 0) NULL,
      RecoveryModel nvarchar(60),
      DifferentialBaseLSN decimal(25, 0) NULL,
      DifferentialBaseGUID uniqueidentifier,
      BackupTypeDescription  nvarchar(60),
      BackupSetGUID uniqueidentifier NULL,
      CompressedBackupSize binary(8),
	  Containment tinyint NOT NULL'

--Common return values for FileListOnly 
SET @FileListSql = 'create table dbo.tblBakFileList
      (
      LogicalName nvarchar(128),
      PhysicalName nvarchar(260),
      Type char(1),
      FileGroupName nvarchar(120),
      Size numeric(20, 0),
      MaxSize numeric(20, 0),
      FileID bigint,
      CreateLSN numeric(25,0),
      DropLSN numeric(25,0) NULL,
      UniqueID uniqueidentifier,
      ReadOnlyLSN numeric(25,0) NULL,
      ReadWriteLSN numeric(25,0),
      BackupSizeInBytes bigint,
      SourceBlockSize int,
      FileGroupID int,
      LogGroupGUID uniqueidentifier,
      DifferentialBaseLSN numeric(25,0) NULL,
      DifferentialBaseGUID uniqueidentifier,
      IsReadOnly bit,
      IsPresent bit,
      TDEThumbprint varbinary(32)'

-- Values specific to SQL Sever 2014 and 2016
IF @ProductVersionNumber in(12, 13)
SET @HeaderSql = @HeaderSql +'
    ,KeyAlgorithm nvarchar(32)
    ,EncryptorThumbprint varbinary(20)
    ,EncryptorType nvarchar(32)' 

--Values specific to SQL Server 2016
IF @ProductVersionNumber in(13)
SET @FileListSql = @FileListSql + '
	,SnapshotURL nvarchar(360)'

--All versions - close statement
SET @HeaderSql = @HeaderSql + ');'
SET @FileListSql = @FileListSql + ');'

--Create Header and FileList tables
EXEC(@HeaderSql)
EXEC(@FileListSql)

SET @Error = 0;

-- get backup header info and display
SET @RestoreStatement = N'RESTORE HEADERONLY
      FROM DISK=N''' + @BackupFile + ''' WITH FILE=1';
INSERT INTO dbo.tblBakHeader
      EXEC('RESTORE HEADERONLY FROM DISK=N''' + @BackupFile + ''' WITH FILE = 1');
SET @Error = @@ERROR;
IF @Error <> 0 GOTO Done;
IF NOT EXISTS(SELECT * FROM dbo.tblBakHeader) GOTO Done;
SELECT
      @OldDatabaseName = DatabaseName,
      @ServerName = ServerName,
      @BackupFinishDate = BackupFinishDate
FROM dbo.tblBakHeader;
IF @NewDatabaseName IS NULL SET @NewDatabaseName = @OldDatabaseName;
SET @Message = N'--Backup source: ServerName=%s, DatabaseName=%s, BackupFinishDate=' +
      CONVERT(nvarchar(23), @BackupFinishDate, 121);
RAISERROR(@Message, 0, 1, @ServerName, @OldDatabaseName) WITH NOWAIT; 

-- get filelist info
SET @RestoreStatement = N'RESTORE FILELISTONLY
      FROM DISK=N''' + @BackupFile + ''' WITH FILE= 1';
INSERT INTO dbo.tblBakFileList
      EXEC(@RestoreStatement);
SET @Error = @@ERROR;
IF @Error <> 0 GOTO Done;
IF NOT EXISTS(SELECT * FROM dbo.tblBakFileList) GOTO Done;
 
-- generate RESTORE DATABASE statement and ALTER DATABASE statements
SET @ChangeLogicalNamesSql = '';
SET @RestoreStatement =
      N'RESTORE DATABASE ' +
      QUOTENAME(@NewDatabaseName) +
      N'
      FROM DISK=N''' +
      @BackupFile + '''' +
      N' 
      WITH REPLACE, 
            FILE=1'
DECLARE FileList CURSOR LOCAL STATIC READ_ONLY FOR
      SELECT
            TYPE AS FileType,
            LogicalName,
            --extract folder name from full path
            LEFT(PhysicalName,
                  LEN(LTRIM(RTRIM(PhysicalName))) -
                  CHARINDEX('\',
                  REVERSE(LTRIM(RTRIM(PhysicalName)))) + 1)
                  AS PhysicalFolderName,
            --extract file name from full path
            LTRIM(RTRIM(RIGHT(PhysicalName,
                  CHARINDEX('\',
                  REVERSE(PhysicalName)) - 1))) AS PhysicalFileName
FROM dbo.tblBakFileList;
 
OPEN FileList;
 
WHILE 1 = 1
BEGIN
      FETCH NEXT FROM FileList INTO
            @FileType, @LogicalName, @PhysicalFolderName, @PhysicalFileName;
      IF @@FETCH_STATUS = -1 BREAK;
 
      -- build new physical name
      SET @NewPhysicalName =
            CASE @FileType
                  WHEN 'D' THEN --database
                        @DataFolder + @NewDatabaseName + RIGHT(@PhysicalFileName, LEN(@PhysicalFileName) - LEN(@OldDatabaseName)) --gets suffix

                  WHEN 'L' THEN --logs
                        @LogFolder + @NewDatabaseName + RIGHT(@PhysicalFileName, LEN(@PhysicalFileName) - LEN(@OldDatabaseName)) --gets suffix                             
            END;
      -- build new logical name
      SET @NewLogicalName = @NewDatabaseName + RIGHT(@LogicalName, LEN(@LogicalName) - LEN(@OldDatabaseName)) --gets suffix

           
      -- generate ALTER DATABASE...MODIFY FILE statement if logical file name is different
      IF @NewLogicalName <> @LogicalName
            SET @ChangeLogicalNamesSql = @ChangeLogicalNamesSql + N'ALTER DATABASE ' + QUOTENAME(@NewDatabaseName) + N'
                  MODIFY FILE (NAME=''' + @LogicalName + N''', NEWNAME=''' + @NewLogicalName + N''');
'


      -- add MOVE option as needed if folder and/or file names are changed
	  IF @PhysicalFolderName + @PhysicalFileName <> @NewPhysicalName
      BEGIN
            SET @RestoreStatement = @RestoreStatement +
                  N',
                  MOVE ''' +
                  @LogicalName +
                  N''' TO ''' +
                  @NewPhysicalName +
                  N'''';
	  END;
END;
CLOSE FileList;
DEALLOCATE FileList;

--execute RESTORE statement
RAISERROR(N'Executing:
%s', 0, 1, @RestoreStatement) WITH NOWAIT
EXEC (@RestoreStatement);
SET @Error = @@ERROR;
IF @Error <> 0 GOTO Done;

--execute ALTER DATABASE statement(s)
IF @ChangeLogicalNamesSql <> ''
BEGIN
      RAISERROR(N'Executing:
%s', 0, 1, @ChangeLogicalNamesSql) WITH NOWAIT
            EXEC (@ChangeLogicalNamesSql);
            SET @Error = @@ERROR;
            IF @Error <> 0 GOTO Done;
      END 
Done:
GO
ALTER DATABASE [$(DatabaseName)] SET MULTI_USER, ENABLE_BROKER WITH NO_WAIT;
IF object_id('dbo.tblBakHeader') IS NOT NULL DROP TABLE dbo.tblBakHeader
IF object_id('dbo.tblBakFileList') IS NOT NULL DROP TABLE dbo.tblBakFileList
