param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFolder,

    [Parameter(Mandatory = $true)]
    [string[]]$FileNames,

    [Parameter(Mandatory = $true)]
    [string]$OutputCsvPath
)

if (-not (Test-Path -LiteralPath $TargetFolder -PathType Container)) {
    throw "指定されたフォルダが存在しません: $TargetFolder"
}

$results = foreach ($fileName in $FileNames) {
    Get-ChildItem `
        -LiteralPath $TargetFolder `
        -File `
        -Recurse `
        -Filter $fileName `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            [PSCustomObject]@{
                FileName      = $_.Name
                FolderPath    = $_.DirectoryName
                LastWriteTime = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
}

$outputDir = Split-Path -Parent $OutputCsvPath
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir -PathType Container)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

$results |
    Sort-Object FolderPath, FileName |
    Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "CSV出力完了: $OutputCsvPath"
