function Invoke-ExecPerUserMFA {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Identity.User.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Guest user handling
    $UserId = $Request.Body.userPrincipalName -match '#EXT#' ? $Request.Body.userId : $Request.Body.userPrincipalName
    $TenantFilter = $Request.Body.tenantFilter
    $State = $Request.Body.State.value ?  $Request.Body.State.value : $Request.Body.State

    $Request = @{
        userId       = $UserId
        TenantFilter = $TenantFilter
        State        = $State
        Headers      = $Headers
        APIName      = $APIName
    }
    try {
        $Result = Set-CIPPPerUserMFA @Request
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Result) }
        })
}
