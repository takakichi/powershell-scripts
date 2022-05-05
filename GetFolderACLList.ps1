#
# get-aclで取得したアクセス権限(FileSystemRights)が
# 32bit整数だった場合に変換を行う
# https://qiita.com/mint_lagoon/items/68198307815deb446987
#
function getACLMap( [string] $acl ) {
    if ( -not ([int] TryParse( $acl, [ref]$aclNum ) )) {
        switch( $actNum ) {
            "Synchronize"    { Write-Output "" }
            "FullControl"    { Write-Output "フルコントロール" }
            "ReadAndExecute" { Write-Output "読み取り/実行" }
            "Modify"         { Write-Output "変更" }
            default          { Write-Output $acl }
        }
    } else {
        $accessMask = [ordered]@{
            [uint32]'0x80000000' = 'Generic_Read'    # 2147483648(読み取り同等)
            [uint32]'0x40000000' = 'Generic_Write'   # 1073741824(書き込み同等)
            [uint32]'0x20000000' = 'Generic_Execute' # 536870912(実行同等)
            [uint32]'0x10000000' = 'Generic_all'     # 268435456(フルコントロール同等)
            [uint32]'0x02000000' = 'MaximumAllowed'  # 33554432(詳細不明/予約済みビット)
            [uint32]'0x01000000' = 'AccessSystemSecurity' # 監査ログ出力設定
            #  [uint32]'0x00100000' = 'Synchronize'
            [uint32]'0x00080000' = 'TakeOwnership'
            [uint32]'0x00040000' = 'ChangePermissions'
            [uint32]'0x00020000' = 'ReadPermissions '
            [uint32]'0x00010000' = 'Delete'
            [uint32]'0x00000100' = 'WriteAttributes'
            [uint32]'0x00000080' = 'ReadAttributes'
            [uint32]'0x00000040' = 'DeleteSubdirectoriesAndFiles'
            [uint32]'0x00000020' = 'Traverse/ExecuteFile'
            [uint32]'0x00000010' = 'WriteExtendedAttributes'
            [uint32]'0x00000008' = 'ReadExtendedAttributes'
            [uint32]'0x00000004' = 'CreateDirectories/AppendData'
            [uint32]'0x00000002' = 'CreateFiles/WriteData'
            [uint32]'0x00000001' = 'ListDirectory/ReadData'
        }
        switch ($aclNum) {
            "2032127" {Write-Output "フルコントロール"; return} 
        }
        Write-Output $accessMask.Keys | ? { $aclNum -band $_ } | % { $accessMask[$_] }
    }
}

#
# 指定したフォルダ以下のフォルダに対する権限を出力する
#
function GetFolderACLList( [string] $folder_name ) {

    $list = Get-ChildItem $folder_name -Force -Recurse | where { $_.mode -match "d" }
    foreach($path in $list){ 
        $acls = Get-ACL -Path $path.fullname
        foreach($acl in $acls){ 
            $values = $acl.Access
            foreach($value in $values){
                #
                # CREATE OWNER,NT AUTHORITY\SYSTEM,BUILDIN\Administrators は出力しない
                # 
                if ( -not ( ($value.IdentityReference).ToString() -eq "CREATOR OWNER") -and
                     -not ( ($value.IdentityReference).ToString() -eq "NT AUTHORITY\SYSTEM") -and
                     -not ( ($value.IdentityReference).ToString() -eq "BUILDIN\Administrators") ) ) {
                    $s = ""
                    foreach ( $SystemRight in $value.FileSystemRights.ToString().split(",") {
                        $txt = getACLMap $SystemRight.Trim()
                        $s = $s + $txt + ","
                    }
                    $s = $s.Trim(",")
                    [String]::Format("{0},{1},{2}", $path.fullname, ($value.IdentityReference).ToString(), $s )
                }
            }
        }
    }
}

GetFolderACLList "c:\temp"
