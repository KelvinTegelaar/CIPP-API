using namespace System.Net

Function Invoke-ExecEditCalendarPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $UserID = ($Request.query.UserID)
    $LoggingName = $Request.query.LoggingName
    $UserToGetPermissions = $Request.query.UserToGetPermissions
    $Tenantfilter = $Request.Query.tenantfilter
    $Permissions = @($Request.query.permissions)
    $folderName = $Request.query.folderName

    try {
        if ($Request.query.removeaccess) {
            $Result = Set-CIPPCalendarPermission -UserID $UserID -folderName $folderName -RemoveAccess $Request.query.removeaccess -TenantFilter $TenantFilter -LoggingName $LoggingName
        } else {
            $Result = Set-CIPPCalendarPermission -UserID $UserID -folderName $folderName -TenantFilter $Tenantfilter -UserToGetPermissions $UserToGetPermissions -LoggingName $LoggingName -Permissions $Permissions
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = $Result }
        })

}
