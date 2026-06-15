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

    $Result = foreach ($TenantFilter in $Tenants) {
        Set-CIPPRetentionCompliancePolicy -TenantFilter $TenantFilter -Template $Template -APIName $APIName -Headers $Headers
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })
}
