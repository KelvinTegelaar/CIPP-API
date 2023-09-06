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


try {
    if ($Request.query.removeaccess) {
        $result = Set-CIPPCalenderPermission -UserID $UserID -folderName $folderName -RemoveAccess $Request.query.removeaccess -TenantFilter $TenantFilter
    }
    else {
        $result = Set-CIPPCalenderPermission -UserID $UserID -folderName $folderName -TenantFilter $Tenantfilter -UserToGetPermissions $UserToGetPermissions -Permissions $Permissions
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
