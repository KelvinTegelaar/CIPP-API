Function Invoke-AddSensitiveInfoType {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.ReadWrite
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
        Set-CIPPSensitiveInfoType -TenantFilter $TenantFilter -Template $Template -APIName $APIName -Headers $Headers
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })
}
