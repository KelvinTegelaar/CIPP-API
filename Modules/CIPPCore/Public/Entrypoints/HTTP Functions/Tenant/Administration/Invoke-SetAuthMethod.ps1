function Invoke-SetAuthMethod {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    Param(
        $Request,
        $TriggerMetadata
    )

    $APIName = "Set Authentication Policy"
    $state = if ($Request.Body.state -eq 'enabled') { $true } else { $false }
    $Tenantfilter = $Request.Body.TenantFilter

    try {
        Set-CIPPAuthenticationPolicy -Tenant $Tenantfilter -APIName $APIName -AuthenticationMethodId $($Request.Body.Id) -Enabled $state
        $StatusCode = [HttpStatusCode]::OK
        $SuccessMessage = "Authentication Policy for $($Request.Body.Id) has been set to $state"
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $SuccessMessage = "Function Error: $($_.InvocationInfo.ScriptLineNumber) - $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{'Results' = "$SuccessMessage" }
        })
}