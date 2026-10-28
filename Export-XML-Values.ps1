
# ==========================================
# XML設定値 一括抽出
# ==========================================

# === 設定項目 ===
$targetFolder = "C:\WebApps"
$extensions = @("*.config", "*.xml")
$outputFile = "C:\Temp\XmlResult.csv"

# 抽出対象（XPath）
$targets = @(
    @{ Name = "ApiUrl"; XPath = "//add[@key='ApiUrl']/@value" },
    @{ Name = "Timeout"; XPath = "//add[@key='Timeout']/@value" },
    @{ Name = "MainDB"; XPath = "//add[@name='MainDB']/@connectionString" },
    @{ Name = "ServerName"; XPath = "//ServerName/text()" }
)

# === 抽出処理 ===
$results = foreach ($file in Get-ChildItem `
    -LiteralPath $targetFolder `
    -File -Recurse |
    Where-Object { $_.Extension -in ($extensions | ForEach-Object {
        $_.Replace("*", "")
    }) }) {

    try {
        # XML読み込み
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $xml.Load($file.FullName)

        foreach ($target in $targets) {

            # XPathで検索
            $nodes = $xml.SelectNodes($target.XPath)

            foreach ($node in $nodes) {

                # 属性・テキスト・要素に対応
                $value = if ($node -is [System.Xml.XmlElement]) {
                    $node.InnerText
                }
                else {
                    $node.Value
                }

                [PSCustomObject]@{
                    FilePath = $file.FullName
                    Name     = $target.Name
                    Value    = $value
                }
            }
        }
    }
    catch {
        Write-Warning "処理失敗: $($file.FullName) - $($_.Exception.Message)"
    }
}

# === CSV出力 ===
$outputDir = Split-Path -Parent $outputFile

if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force |
        Out-Null
}

$results | Export-Csv `
    -LiteralPath $outputFile `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host "抽出完了: $outputFile"
