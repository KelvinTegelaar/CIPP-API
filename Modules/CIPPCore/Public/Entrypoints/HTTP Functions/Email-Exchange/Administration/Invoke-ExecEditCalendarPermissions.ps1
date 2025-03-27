using namespace System.Net

function Invoke-ExecEditCalendarPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Extract parameters from query or body
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.userid ?? $Request.Body.userid
    $UserToGetPermissions = $Request.Query.UserToGetPermissions ?? $Request.Body.UserToGetPermissions.value
    $Permissions = $Request.Query.Permissions ?? $Request.Body.Permissions.value
    $FolderName = $Request.Query.FolderName ?? $Request.Body.FolderName
    $RemoveAccess = $Request.Query.RemoveAccess ?? $Request.Body.RemoveAccess.value

    try {
        if ($RemoveAccess) {
            $Result = Set-CIPPCalendarPermission -Headers $Headers -UserID $UserID -FolderName $FolderName -RemoveAccess $RemoveAccess -TenantFilter $TenantFilter
        } else {
            $Result = Set-CIPPCalendarPermission -Headers $Headers -UserID $UserID -FolderName $FolderName -TenantFilter $TenantFilter -UserToGetPermissions $UserToGetPermissions -Permissions $Permissions
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        Write-Warning "Error in ExecEditCalendarPermissions: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}
