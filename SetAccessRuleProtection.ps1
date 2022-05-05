#
# 継承の無効化
#
function SetAccessRuleProtection( [string] $folder_name ) {
	$acl = Get-Acl $folder_name
	$acl.SetAccessRuleProtection( $true, $true )
	$acl | Set-Acl folder_name
}

SetAccessRuleProtection "c:\temp"
