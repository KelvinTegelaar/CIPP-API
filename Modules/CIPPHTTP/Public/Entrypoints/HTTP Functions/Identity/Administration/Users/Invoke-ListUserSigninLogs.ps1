Function Invoke-ListUserSigninLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $top = $Request.Query.top ? $Request.Query.top : 50


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID
    $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$UserID')&`$top=$top&`$orderby=createdDateTime desc"

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
