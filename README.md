# powershell-scripts

## Find-FilesAndExportCsv.ps1

指定フォルダ配下（サブフォルダ含む）から複数のファイル名を検索し、存在するフォルダと更新日時を CSV 出力します。

```powershell
.\Find-FilesAndExportCsv.ps1 `
  -TargetFolder "C:\Work" `
  -FileNames @("appsettings.json", "web.config", "*.config") `
  -OutputCsvPath "C:\Temp\search-result.csv"
```