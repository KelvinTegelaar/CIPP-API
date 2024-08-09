function Invoke-ExecPerUserMFAAllUsers {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Identity.User.ReadWrite
    #>
    Param(
        $Request,
        $TriggerMetadata
    )
    $TenantFilter = $request.query.TenantFilter
    $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter
    $Request = @{
        userId        = $Users.id
        TenantFilter  = $tenantfilter
        State         = $Request.query.State
        executingUser = $Request.Headers.'x-ms-client-principal'
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
