function Invoke-ExecPerUserMFAAllUsers {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Identity.User.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # XXX Seems to be an unused endpoint? - Bobby

    $TenantFilter = $request.Query.tenantFilter
    $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter
    $Request = @{
        userId       = $Users.id
        TenantFilter = $TenantFilter
        State        = $Request.Query.State
        Headers      = $Request.Headers
        APIName      = $APIName
    }
    $Result = Set-CIPPPerUserMFA @Request
    $Body = @{
        Results = @($Result)
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
