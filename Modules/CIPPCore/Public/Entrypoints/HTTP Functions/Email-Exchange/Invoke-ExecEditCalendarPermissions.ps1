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
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Extract parameters from query or body
    $TenantFilter = if ($Request.query.TenantFilter) { $Request.query.TenantFilter } else { $Request.Body.TenantFilter }
    $UserID = if ($Request.query.UserID) { $Request.query.UserID } else { $Request.Body.UserID }
    $UserToGetPermissions = if ($Request.query.UserToGetPermissions) { $Request.query.UserToGetPermissions } else { $Request.Body.UserToGetPermissions.value }
    $Permissions = if ($Request.query.Permissions) { @($Request.query.Permissions) } else { @($Request.Body.Permissions.value) }
    $FolderName = if ($Request.query.FolderName) { $Request.query.FolderName } else { $Request.Body.FolderName }
    $RemoveAccess = if ($Request.query.RemoveAccess) { $Request.query.RemoveAccess } else { $Request.Body.RemoveAccess.value }

    try {
        if ($RemoveAccess) {
            $result = Set-CIPPCalendarPermission -UserID $UserID -FolderName $FolderName -RemoveAccess $RemoveAccess -TenantFilter $TenantFilter
        } else {
            $result = Set-CIPPCalendarPermission -UserID $UserID -FolderName $FolderName -TenantFilter $TenantFilter -UserToGetPermissions $UserToGetPermissions -Permissions $Permissions
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
