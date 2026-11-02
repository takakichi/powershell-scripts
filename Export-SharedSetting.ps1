
# Export-ShareSettings.ps1
# Windows PowerShell 5.1 / 管理者権限

param(
    [string]$BackupDir = "C:\ShareMigration\Backup"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# 管理共有、特殊共有を除外
$shares = @(
    Get-SmbShare | Where-Object {
        $_.Special -eq $false -and
        $_.ShareType -eq "FileSystemDirectory"
    }
)

# 共有フォルダ設定
$shares |
    Select-Object Name, Path, Description,
        FolderEnumerationMode, CachingMode,
        EncryptData |
    Export-Csv "$BackupDir\shares.csv" `
        -NoTypeInformation -Encoding UTF8

# 共有アクセス権限
$access = foreach ($share in $shares) {
    Get-SmbShareAccess -Name $share.Name |
        Select-Object Name, AccountName,
            AccessControlType, AccessRight
}

$access |
    Export-Csv "$BackupDir\share-access.csv" `
        -NoTypeInformation -Encoding UTF8

# NTFS権限（共有ルートを含む）
# icacls /restore は親フォルダを基準に復元する
$index = 0

foreach ($share in $shares) {
    $index++
    $path = $share.Path.TrimEnd('\')
    $parent = Split-Path $path -Parent
    $leaf = Split-Path $path -Leaf
    $aclFile = Join-Path $BackupDir "acl-$index.txt"

    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "フォルダが存在しません: $path"
    }

    Push-Location $parent
    try {
        & icacls.exe $leaf /save $aclFile /T
        if ($LASTEXITCODE -ne 0) {
            throw "ACL保存失敗: $path"
        }
    }
    finally {
        Pop-Location
    }

    [PSCustomObject]@{
        Name    = $share.Name
        Path    = $path
        AclFile = "acl-$index.txt"
    } | Export-Csv "$BackupDir\acl-index.csv" `
        -NoTypeInformation -Encoding UTF8 -Append
}

Write-Host "エクスポート完了: $BackupDir"
