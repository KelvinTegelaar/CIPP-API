function Invoke-ExecPerUserMFA {
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

    $Request = @{
        userId        = $Request.Body.userId
        TenantFilter  = $Request.Body.TenantFilter
        State         = $Request.Body.State.value ?  $Request.Body.State.value : $Request.Body.State
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
