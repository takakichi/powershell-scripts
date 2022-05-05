
#
# Windows Folder Permisstion "Add FullControl"
#
Function SetAccessFullControl ( [string] $folder_name, [string] $user ) {
  $acl = Get-Acl $folder_name
  # ユーザー名, アクセス権, 下位フォルダへ継承, 下位オブジェクトへ継承, 継承の制限, アクセス許可
  $permissions = ( $user, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow" )
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule $permissions
  $acl.SetAccessRule($rule)
  $acl | Set-Acl $folder_name
}

SetAccessFullControl "c:\temp" "domain/user"
