using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$UserID = ($request.query.UserID)
$UserToGetPermissions = $Request.query.UserToGetPermissions
$Tenantfilter = $request.Query.tenantfilter
$Permissions = @($Request.query.permissions)
$folderName = $Request.query.folderName


$CalParam = [PSCustomObject]@{
    Identity     = "$($UserID):\$folderName"
    AccessRights = @($Permissions)
    User         = $UserToGetPermissions
}
try {
    if ($Request.query.removeaccess) {
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Remove-MailboxFolderPermission" -cmdParams @{Identity = "$($UserID):\$folderName"; User = $Request.query.RemoveAccess }
        $Result = "Successfully removed access for $($Request.query.RemoveAccess) from calender $($CalParam.Identity)"
    }
    else {
        try {
            $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Set-MailboxFolderPermission" -cmdParams $CalParam -Anchor $($UserID)
        }
        catch {
            $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Add-MailboxFolderPermission" -cmdParams $CalParam -Anchor $($UserID)
        }
        Write-LogMessage -API 'List Calendar Permissions' -tenant $tenantfilter -message "Calendar permissions listed for $($tenantfilter)" -sev Debug
    
        $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $UserToGetPermissions now has $Permissions permissions on this folder."
    }
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception
    $Result = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = $Result }
    })
