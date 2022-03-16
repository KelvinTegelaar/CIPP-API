using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
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
    $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet "Add-MailboxFolderPermission" -cmdParams $CalParam
    Log-request -API 'List Calendar Permissions' -tenant $tenantfilter -message "Calendar permissions listed for $($tenantfilter)" -sev Debug
    $StatusCode = [HttpStatusCode]::OK
    $Result = "Succesfully set permissions on folder $($CalParam.Identity). The user $UserToGetPermissions now has $Permissions permissions on this folder."
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception
    $StatusCode = [HttpStatusCode]::Forbidden
    $Result = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Result)
    })
