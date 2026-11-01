
#Requires -Version 5.1

<#
.SYNOPSIS
    SQL Serverのデータベース設定をCSV出力します。

.DESCRIPTION
    ユーザーデータベースを対象に、以下を出力します。
      1. Database.csv
      2. DatabaseOptions.csv
      3. DatabaseFiles.csv
      4. DatabasePermissions.csv

    Windows認証を使用します。
    Excelや追加のPowerShellモジュールは不要です。

.EXAMPLE
    .\Export-SqlDatabaseSettings.ps1 `
        -ServerInstance "SQLSERVER01" `
        -OutputDirectory "C:\Work\DB_Settings"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

# ==========================================
# SQL実行共通関数
# ==========================================
function Invoke-SqlQuery {
    param (
        [string]$Database = "master",
        [string]$Query
    )

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"] = $ServerInstance
    $builder["Initial Catalog"] = $Database
    $builder["Integrated Security"] = $true
    $builder["Connect Timeout"] = 15
    $builder["Application Name"] = "Export-SqlDatabaseSettings"

    $connection = New-Object System.Data.SqlClient.SqlConnection(
        $builder.ConnectionString
    )

    try {
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter(
            $command
        )

        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)

        # DataRowをPowerShellオブジェクトに変換
        $rows = foreach ($row in $table.Rows) {
            $item = [ordered]@{}

            foreach ($column in $table.Columns) {
                $value = $row[$column.ColumnName]

                if ($value -is [DBNull]) {
                    $value = $null
                }

                $item[$column.ColumnName] = $value
            }

            [PSCustomObject]$item
        }

        return $rows
    }
    finally {
        if ($connection) {
            $connection.Dispose()
        }
    }
}

# ==========================================
# CSV出力共通関数
# ==========================================
function Export-ResultCsv {
    param (
        [object[]]$Data,
        [string]$FileName,
        [string[]]$Columns
    )

    $path = Join-Path $OutputDirectory $FileName

    # 取得結果が0件でもヘッダーを出力
    if ($Data.Count -eq 0) {
        $header = ($Columns | ForEach-Object {
            '"' + $_.Replace('"', '""') + '"'
        }) -join ","

        Set-Content -Path $path -Value $header -Encoding UTF8
    }
    else {
        $Data |
            Select-Object -Property $Columns |
            Export-Csv -Path $path `
                -NoTypeInformation `
                -Encoding UTF8
    }

    Write-Host ("出力: {0} ({1}件)" -f $path, $Data.Count)
}

# ==========================================
# メイン処理
# ==========================================
try {
    Write-Host "SQL Server設定情報の取得を開始します。"
    Write-Host "接続先: $ServerInstance"

    # --------------------------------------
    # 1. データベース基本設定
    # --------------------------------------
    $sqlDatabase = @"
SELECT
    name AS DatabaseName,
    collation_name AS Collation,
    compatibility_level AS CompatibilityLevel,
    recovery_model_desc AS RecoveryModel,
    SUSER_SNAME(owner_sid) AS OwnerName,
    state_desc AS DatabaseState,
    user_access_desc AS UserAccess
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
"@

    $databases = @(
        Invoke-SqlQuery -Query $sqlDatabase
    )

    # --------------------------------------
    # 2. データベースオプション
    # --------------------------------------
    $sqlOptions = @"
SELECT
    name AS DatabaseName,
    is_auto_close_on AS AutoClose,
    is_auto_shrink_on AS AutoShrink,
    is_auto_create_stats_on AS AutoCreateStatistics,
    is_auto_update_stats_on AS AutoUpdateStatistics,
    is_auto_update_stats_async_on AS AutoUpdateStatsAsync,
    is_read_committed_snapshot_on AS ReadCommittedSnapshot,
    snapshot_isolation_state_desc AS SnapshotIsolation,
    is_trustworthy_on AS Trustworthy,
    is_db_chaining_on AS DbChaining,
    is_parameterization_forced AS ParameterizationForced,
    is_ansi_null_default_on AS AnsiNullDefault,
    is_ansi_nulls_on AS AnsiNulls,
    is_ansi_padding_on AS AnsiPadding,
    is_ansi_warnings_on AS AnsiWarnings,
    is_arithabort_on AS ArithAbort,
    is_concat_null_yields_null_on AS ConcatNullYieldsNull,
    is_quoted_identifier_on AS QuotedIdentifier,
    is_recursive_triggers_on AS RecursiveTriggers,
    is_broker_enabled AS BrokerEnabled,
    is_query_store_on AS QueryStoreEnabled
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
"@

    $options = @(
        Invoke-SqlQuery -Query $sqlOptions
    )

    # --------------------------------------
    # 3. データベースファイル設定
    # --------------------------------------
    $sqlFiles = @"
SELECT
    DB_NAME(database_id) AS DatabaseName,
    name AS LogicalFileName,
    physical_name AS PhysicalFileName,
    type_desc AS FileType,
    size * 8.0 / 1024 AS SizeMB,
    CASE
        WHEN max_size = -1 THEN 'UNLIMITED'
        ELSE CONVERT(varchar(30), max_size * 8.0 / 1024)
    END AS MaxSizeMB,
    growth AS GrowthValue,
    CASE
        WHEN is_percent_growth = 1 THEN 'PERCENT'
        ELSE 'PAGES'
    END AS GrowthUnit,
    CASE
        WHEN is_percent_growth = 1
            THEN CONVERT(varchar(30), growth) + '%'
        ELSE
            CONVERT(varchar(30), growth * 8.0 / 1024) + ' MB'
    END AS GrowthDisplay,
    state_desc AS FileState
FROM sys.master_files
WHERE database_id > 4
ORDER BY database_id, file_id;
"@

    $files = @(
        Invoke-SqlQuery -Query $sqlFiles
    )

    # --------------------------------------
    # 4. データベースユーザー・権限
    # --------------------------------------
    $permissions = New-Object System.Collections.Generic.List[object]

    foreach ($db in $databases) {

        $dbName = $db.DatabaseName

        Write-Host "ユーザー・権限取得: $dbName"

        # ユーザー一覧
        $sqlUsers = @"
SELECT
    'USER' AS RecordType,
    DB_NAME() AS DatabaseName,
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    dp.authentication_type_desc AS AuthenticationType,
    dp.default_schema_name AS DefaultSchema,
    CAST(NULL AS sysname) AS RoleName,
    CAST(NULL AS nvarchar(60)) AS PermissionState,
    CAST(NULL AS nvarchar(128)) AS PermissionName,
    CAST(NULL AS nvarchar(60)) AS ClassDescription,
    CAST(NULL AS nvarchar(776)) AS SecurableName
FROM sys.database_principals dp
WHERE dp.principal_id > 4
  AND dp.type IN ('S', 'U', 'G', 'E', 'X', 'C', 'K')
ORDER BY dp.name;
"@

        $users = @(
            Invoke-SqlQuery -Database $dbName -Query $sqlUsers
        )

        foreach ($item in $users) {
            $permissions.Add($item)
        }

        # ロール所属
        $sqlRoles = @"
SELECT
    'ROLE' AS RecordType,
    DB_NAME() AS DatabaseName,
    member.name AS PrincipalName,
    member.type_desc AS PrincipalType,
    CAST(NULL AS nvarchar(60)) AS AuthenticationType,
    CAST(NULL AS sysname) AS DefaultSchema,
    role.name AS RoleName,
    CAST(NULL AS nvarchar(60)) AS PermissionState,
    CAST(NULL AS nvarchar(128)) AS PermissionName,
    CAST(NULL AS nvarchar(60)) AS ClassDescription,
    CAST(NULL AS nvarchar(776)) AS SecurableName
FROM sys.database_role_members drm
INNER JOIN sys.database_principals role
    ON drm.role_principal_id = role.principal_id
INNER JOIN sys.database_principals member
    ON drm.member_principal_id = member.principal_id
ORDER BY member.name, role.name;
"@

        $roles = @(
            Invoke-SqlQuery -Database $dbName -Query $sqlRoles
        )

        foreach ($item in $roles) {
            $permissions.Add($item)
        }

        # 明示的な権限
        $sqlPermissions = @"
SELECT
    'PERMISSION' AS RecordType,
    DB_NAME() AS DatabaseName,
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    CAST(NULL AS nvarchar(60)) AS AuthenticationType,
    CAST(NULL AS sysname) AS DefaultSchema,
    CAST(NULL AS sysname) AS RoleName,
    perm.state_desc AS PermissionState,
    perm.permission_name AS PermissionName,
    perm.class_desc AS ClassDescription,
    CASE perm.class
        WHEN 0 THEN DB_NAME()
        WHEN 1 THEN
            OBJECT_SCHEMA_NAME(perm.major_id) + '.' +
            OBJECT_NAME(perm.major_id)
        WHEN 3 THEN SCHEMA_NAME(perm.major_id)
        ELSE CONVERT(nvarchar(30), perm.major_id)
    END AS SecurableName
FROM sys.database_permissions perm
INNER JOIN sys.database_principals dp
    ON perm.grantee_principal_id = dp.principal_id
ORDER BY dp.name, perm.permission_name;
"@

        $dbPermissions = @(
            Invoke-SqlQuery -Database $dbName -Query $sqlPermissions
        )

        foreach ($item in $dbPermissions) {
            $permissions.Add($item)
        }
    }

    # --------------------------------------
    # 5. CSV出力
    # --------------------------------------
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory `
            -Path $OutputDirectory `
            -Force | Out-Null
    }

    Export-ResultCsv `
        -Data $databases `
        -FileName "Database.csv" `
        -Columns @(
            "DatabaseName",
            "Collation",
            "CompatibilityLevel",
            "RecoveryModel",
            "OwnerName",
            "DatabaseState",
            "UserAccess"
        )

    Export-ResultCsv `
        -Data $options `
        -FileName "DatabaseOptions.csv" `
        -Columns @(
            "DatabaseName",
            "AutoClose",
            "AutoShrink",
            "AutoCreateStatistics",
            "AutoUpdateStatistics",
            "AutoUpdateStatsAsync",
            "ReadCommittedSnapshot",
            "SnapshotIsolation",
            "Trustworthy",
            "DbChaining",
            "ParameterizationForced",
            "AnsiNullDefault",
            "AnsiNulls",
            "AnsiPadding",
            "AnsiWarnings",
            "ArithAbort",
            "ConcatNullYieldsNull",
            "QuotedIdentifier",
            "RecursiveTriggers",
            "BrokerEnabled",
            "QueryStoreEnabled"
        )

    Export-ResultCsv `
        -Data $files `
        -FileName "DatabaseFiles.csv" `
        -Columns @(
            "DatabaseName",
            "LogicalFileName",
            "PhysicalFileName",
            "FileType",
            "SizeMB",
            "MaxSizeMB",
            "GrowthValue",
            "GrowthUnit",
            "GrowthDisplay",
            "FileState"
        )

    Export-ResultCsv `
        -Data @($permissions.ToArray()) `
        -FileName "DatabasePermissions.csv" `
        -Columns @(
            "RecordType",
            "DatabaseName",
            "PrincipalName",
            "PrincipalType",
            "AuthenticationType",
            "DefaultSchema",
            "RoleName",
            "PermissionState",
            "PermissionName",
            "ClassDescription",
            "SecurableName"
        )

    Write-Host ""
    Write-Host "すべてのCSV出力が完了しました。"
}
catch {
    Write-Error ("処理に失敗しました: " + $_.Exception.Message)
    exit 1
}
