Function Invoke-AddRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Template = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $Tenants = ($Request.Body.selectedTenants).value

    # Tenant scope: a scoped role must not reach tenants outside its allowed set through selectedTenants.
    $AllowedTenants = Test-CippAccess -Request $Request -TenantList
    if ($AllowedTenants -ne 'AllTenants') {
        $AllowedTenantList = (Get-Tenants -IncludeErrors) | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
    }

    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            @{ resultText = Set-CIPPRetentionCompliancePolicy -TenantFilter $TenantFilter -Template $Template -APIName $APIName -Headers $Headers; state = 'success' }
        } catch {
            @{ resultText = $_.Exception.Message; state = 'error' }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total @($Result).Count -Failed @($Result).Where({ $_.state -eq 'error' }).Count
            Body       = @{Results = @($Result) }
        })
}
