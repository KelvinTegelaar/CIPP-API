using namespace System.Net

Function Invoke-AddCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenants = $Request.body.tenantFilter.value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $results = foreach ($Tenant in $tenants) {
        try {
            $CAPolicy = New-CIPPCAPolicy -replacePattern $Request.body.replacename -Overwrite $request.body.overwrite -TenantFilter $tenant -state $request.body.NewState -RawJSON $Request.body.RawJSON -APIName $APIName -Headers $Request.Headers
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($Displayname)" -Sev 'Info'
            "Successfully added Conditional Access Policy for $($Tenant)"
        } catch {
            "Failed to add policy for $($Tenant): $($_.Exception.Message)"
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Failed to add Conditional Access Policy $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
