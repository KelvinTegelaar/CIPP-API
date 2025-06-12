function Invoke-ExecDismissRiskyUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SuspectUser = $Request.Query.userId ?? $Request.Body.userId
    $userDisplayName = $Request.Query.userDisplayName ?? $Request.Body.userDisplayName

    $GraphRequest = @{
        'uri'         = 'https://graph.microsoft.com/beta/riskyUsers/dismiss'
        'tenantid'    = $TenantFilter
        'type'        = 'POST'
        'contentType' = 'application/json; charset=utf-8'
        'body'        = @{
            'userIds' = @($SuspectUser)
        } | ConvertTo-Json
    }

    try {
        $GraphResults = New-GraphPostRequest @GraphRequest
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Dismissed user risk for $userDisplayName" -sev 'Info'
        $Result = "Successfully dismissed User Risk for user $userDisplayName. $GraphResults"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to dismiss user risk for $userDisplayName. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Result -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
