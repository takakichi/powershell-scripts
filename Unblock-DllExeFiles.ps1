[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$TargetFolder = ".",

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# パスの正規化・存在確認
if (-not (Test-Path -Path $TargetFolder)) {
    Write-Error "指定されたフォルダーが見つかりません: $TargetFolder"
    exit 1
}

$resolvedPath = (Resolve-Path -Path $TargetFolder).Path
Write-Host "探索対象フォルダー: $resolvedPath" -ForegroundColor Cyan
Write-Host "ブロックされた DLL / EXE ファイルを検索中..." -ForegroundColor Cyan

# 対象拡張子
$extensions = @('.dll', '.exe')

# ブロック済みファイルの一覧を取得
$blockedFiles = Get-ChildItem -Path $resolvedPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $extensions -contains $_.Extension.ToLower()
} | Where-Object {
    # Zone.Identifier ストリームが存在するか確認
    $null -ne (Get-Item -LiteralPath $_.FullName -Stream "Zone.Identifier" -ErrorAction SilentlyContinue)
}

if (-not $blockedFiles -or $blockedFiles.Count -eq 0) {
    Write-Host "ブロックされている DLL / EXE ファイルは見つかりませんでした。" -ForegroundColor Green
    return
}

# 検出結果の概要を表示
Write-Host "`n以下の $($blockedFiles.Count) 件のファイルでブロック情報が検出されました:`n" -ForegroundColor Yellow
$blockedFiles | Select-Object Name, DirectoryName | Format-Table -AutoSize

# 確認プロンプト（-Force スイッチが指定されている場合はスキップ）
if (-not $Force) {
    $prompt = Read-Host "上記 $($blockedFiles.Count) 件のファイルのブロックを一括解除しますか？ (y/N)"
    if ($prompt -notin @('y', 'Y')) {
        Write-Host "処理をキャンセルしました。" -ForegroundColor DarkGray
        return
    }
}

Write-Host "`nブロック解除処理を開始します..." -ForegroundColor Cyan
$successCount = 0
$failCount = 0

foreach ($file in $blockedFiles) {
    $targetDesc = "$($file.Name) ($($file.FullName))"

    if ($PSCmdlet.ShouldProcess($targetDesc, "ブロック情報の解除 (Unblock-File)")) {
        try {
            Unblock-File -LiteralPath $file.FullName -ErrorAction Stop
            Write-Host " [解除成功] $($file.Name)" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Warning " [解除失敗] $($file.FullName) - $($_.Exception.Message)"
            $failCount++
        }
    }
}

# 最終結果のサマリー
Write-Host "`n処理完了:" -ForegroundColor Cyan
Write-Host "  成功: $successCount 件" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  失敗: $failCount 件" -ForegroundColor Red
}
