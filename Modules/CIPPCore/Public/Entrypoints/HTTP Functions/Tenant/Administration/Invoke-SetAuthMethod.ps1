function Invoke-SetAuthMethod {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $State = if ($Request.Body.state -eq 'enabled') { $true } else { $false }
    $TenantFilter = $Request.Body.tenantFilter

    try {
        $Result = Set-CIPPAuthenticationPolicy -Tenant $TenantFilter -APIName $APIName -AuthenticationMethodId $($Request.Body.Id) -Enabled $State -Headers $Request.Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{'Results' = "$Result" }
        })
}
