Function Invoke-ListUserSigninLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Lists recent sign-in log entries for a specific Entra ID user, ordered by most recent.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $top = [Math]::Min([Math]::Max(($Request.Query.top -as [int]) ?? 50, 1), 1000)


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID
    $SafeUserId = [uri]::EscapeDataString((ConvertTo-CIPPODataFilterValue -Value $UserID))
    $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$SafeUserId')&`$top=$top&`$orderby=createdDateTime desc"

    try {
        $Result = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -verbose
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve Sign In report for user $UserID : Error: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Result)
        })
}
