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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.Query.tenantfilter
    $SuspectUser = $Request.Query.userid
    $userDisplayName = $Request.Query.userDisplayName

    $GraphRequest = @{
        'uri'           = 'https://graph.microsoft.com/beta/riskyUsers/dismiss'
        'tenantid'      = $TenantFilter
        'type'          = 'POST'
        'contentType'   = 'application/json; charset=utf-8'
        'body'          = @{
            'userIds' = @($SuspectUser)
        } | ConvertTo-Json
    }

    try {
        $GraphResults = New-GraphPostRequest @GraphRequest
        Write-LogMessage -API 'DismissRiskyUser' -tenant $TenantFilter -message "Dismissed user risk for $userDisplayName" -sev 'Info'

        $ResponseBody = [pscustomobject]@{ 'Results' = "Successfully dismissed User Risk for user $userDisplayName. $GraphResults" }
    } catch {
        $ResponseBody = [pscustomobject]@{ 'Results' = "Failed to execute dismissal. $($_.Exception.Message)" }
        Write-LogMessage -API 'DismissRiskyUser' -tenant $TenantFilter -message "Failed to dismiss user risk for $userDisplayName" -sev 'Error'
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $ResponseBody
    })
}
