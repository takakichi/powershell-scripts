#
# Windows Folder Permisstion "Add Read And Execute Permission"
#

Function SetPermReadOnly ( [String] $folder_name, [String] $user ) {
  $acl   = Get-Acl $folder_name
  $permissions = ( $user, "ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow" )
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule $permissions
  $acl.SetAccessRule($rule)
  $acl | Set-Acl $folder_name
}

SetPermReadOnly "c:\temp" "hekiheki"
