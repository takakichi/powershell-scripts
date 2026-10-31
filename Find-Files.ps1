[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$TargetFolder,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputCsvPath
)

# --------------------------------------------------
# 検索対象ファイル名（正規表現）
# --------------------------------------------------
$TargetPatternList = @(
    'app\.exe',
    'common\.dll',
    'config\.json',
    'setting\.xml',
    '.*\.log'
)

$TargetRegex = '^(?:' + ($TargetPatternList -join '|') + ')$'

# --------------------------------------------------
# 初期設定
# --------------------------------------------------
$resolvedTargetFolder = (Resolve-Path -LiteralPath $TargetFolder).ProviderPath

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$pendingDirs = [System.Collections.Generic.Stack[string]]::new()

$pendingDirs.Push($resolvedTargetFolder)

$skippedCount = 0

Write-Host "ファイル検索を開始します: $resolvedTargetFolder" -ForegroundColor Cyan

# --------------------------------------------------
# フォルダを順番に検索
# --------------------------------------------------
while ($pendingDirs.Count -gt 0) {

    $currentDir = $pendingDirs.Pop()

    # ファイル一覧取得
    try {
        $files = [System.IO.Directory]::GetFiles($currentDir)
    }
    catch {
        Write-Warning "ファイル一覧取得不可: $currentDir - $($_.Exception.Message)"
        $skippedCount++
        $files = @()
    }

    # 対象ファイルの情報取得
    foreach ($filePath in $files) {

        $fileName = [System.IO.Path]::GetFileName($filePath)

        if ($fileName -notmatch $TargetRegex) {
            continue
        }

        try {
            $fileInfo = [System.IO.FileInfo]::new($filePath)

            $fileVersion = ""
            $productVersion = ""
            $productName = "" 

            # EXE・DLLのみバージョン情報を取得
            if ($fileInfo.Extension -in @('.exe', '.dll')) {
                $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($filePath)

                $fileVersion = $versionInfo.FileVersion
                $productVersion = $versionInfo.ProductVersion
                $productName = $versionInfo.ProductName
            }

            $results.Add([PSCustomObject]@{
                'ファイル名'         = $fileInfo.Name
                'ファイルパス'       = $fileInfo.FullName
                'タイムスタンプ'     = $fileInfo.LastWriteTime.ToString('yyyy/MM/dd HH:mm:ss')
                'ファイルサイズ'     = $fileInfo.Length
                'ファイルバージョン' = $fileVersion
                '製品バージョン'     = $productVersion
                '製品名'             = $productName
            })
        }
        catch {
            Write-Warning "ファイル情報取得不可: $filePath - $($_.Exception.Message)"
            $skippedCount++
        }
    }

    # サブフォルダ一覧取得
    try {
        $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
    }
    catch {
        Write-Warning "サブフォルダ一覧取得不可: $currentDir - $($_.Exception.Message)"
        $skippedCount++
        continue
    }

    foreach ($subDir in $subDirs) {

        try {
            $dirInfo = [System.IO.DirectoryInfo]::new($subDir)

            # ジャンクション・シンボリックリンクを除外
            if (($dirInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }

            $pendingDirs.Push($subDir)
        }
        catch {
            Write-Warning "フォルダ情報取得不可: $subDir - $($_.Exception.Message)"
            $skippedCount++
        }
    }
}

# --------------------------------------------------
# CSV出力
# --------------------------------------------------
try {
    $outputDir = Split-Path -Path $OutputCsvPath -Parent

    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
    }

    if ($results.Count -gt 0) {
        $results |
            Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

        Write-Host "検索完了: $($results.Count) 件" -ForegroundColor Green
        Write-Host "出力先: $OutputCsvPath"
    }
    else {
        Write-Host "対象ファイルは見つかりませんでした。" -ForegroundColor Yellow
    }

    if ($skippedCount -gt 0) {
        Write-Warning "検索中に $skippedCount 件の取得エラーが発生しました。"
    }
}
catch {
    Write-Error "CSV出力に失敗しました: $($_.Exception.Message)"
}
