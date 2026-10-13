/*
    Grant Database Watcher the permissions it needs on an Azure SQL Managed Instance.

    Run this in the `master` database of the SQL MI, connected as a Microsoft Entra
    administrator. Set @watcherName below - it appears in exactly one place.

    CRITICAL - read before editing:

    When the watcher connects it VALIDATES the exact permission set it holds. It
    disconnects if permissions are insufficient OR if unnecessary permissions are
    granted. Do not add the login to any server role, do not grant anything extra,
    and do not grant it db_datareader "just to be safe". Extra permissions BREAK
    data collection just as reliably as missing ones.

    Reference:
    https://learn.microsoft.com/azure/azure-sql/database-watcher-manage
*/

-- ---------------------------------------------------------------------------
-- SET THIS ONCE - the watcher resource name (terraform output watcher_name).
-- ---------------------------------------------------------------------------
DECLARE @watcherName sysname =  N'<watcher-name>';

/*
    The whole script is one batch so the name is declared exactly once. msdb work
    goes through msdb.sys.sp_executesql instead of USE + GO, because GO ends the
    batch and would discard @watcherName.
*/

IF @watcherName = N'<watcher-name>'
    THROW 50000, 'Set @watcherName to your watcher name before running this script.', 1;

DECLARE @login nvarchar(max) = QUOTENAME(@watcherName);
DECLARE @sql nvarchar(max);

-- ---------------------------------------------------------------------------
-- 1. Create the Entra login for the watcher's managed identity
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @watcherName)
BEGIN
    SET @sql = N'CREATE LOGIN ' + @login + N' FROM EXTERNAL PROVIDER;';
    EXEC sys.sp_executesql @sql;
END

-- ---------------------------------------------------------------------------
-- 2. Server-level permissions (SQL MI)
-- ---------------------------------------------------------------------------
SET @sql = N'
    GRANT CONNECT SQL                   TO ' + @login + N';
    GRANT CONNECT ANY DATABASE          TO ' + @login + N';
    GRANT VIEW ANY DATABASE             TO ' + @login + N';
    GRANT VIEW ANY DEFINITION           TO ' + @login + N';
    GRANT VIEW SERVER PERFORMANCE STATE TO ' + @login + N';';
EXEC sys.sp_executesql @sql;

-- ---------------------------------------------------------------------------
-- 3. msdb permissions - required for SQL Agent job and backup datasets
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM msdb.sys.database_principals WHERE name = @watcherName)
BEGIN
    SET @sql = N'CREATE USER ' + @login + N' FOR LOGIN ' + @login + N';';
    EXEC msdb.sys.sp_executesql @sql;
END

SET @sql = N'
    GRANT SELECT ON dbo.backupmediafamily TO ' + @login + N';
    GRANT SELECT ON dbo.backupmediaset    TO ' + @login + N';
    GRANT SELECT ON dbo.backupset         TO ' + @login + N';
    GRANT SELECT ON dbo.suspect_pages     TO ' + @login + N';
    GRANT SELECT ON dbo.syscategories     TO ' + @login + N';
    GRANT SELECT ON dbo.sysjobactivity    TO ' + @login + N';
    GRANT SELECT ON dbo.sysjobhistory     TO ' + @login + N';
    GRANT SELECT ON dbo.sysjobs           TO ' + @login + N';
    GRANT SELECT ON dbo.sysjobsteps       TO ' + @login + N';
    GRANT SELECT ON dbo.sysoperators      TO ' + @login + N';
    GRANT SELECT ON dbo.syssessions       TO ' + @login + N';';
EXEC msdb.sys.sp_executesql @sql;

-- ---------------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------------
SELECT sp.name, sp.type_desc, p.permission_name, p.state_desc
FROM sys.server_principals sp
LEFT JOIN sys.server_permissions p ON p.grantee_principal_id = sp.principal_id
WHERE sp.name = @watcherName;

-- Must return zero rows. Membership in ANY server role breaks data collection.
SELECT r.name AS role_name
FROM sys.server_role_members rm
JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name = @watcherName;
GO
