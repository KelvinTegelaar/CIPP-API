Function Invoke-AddDlpCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.DlpCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Template = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $Tenants = ($Request.Body.selectedTenants).value

    $Result = foreach ($TenantFilter in $Tenants) {
        Set-CIPPDlpCompliancePolicy -TenantFilter $TenantFilter -Template $Template -APIName $APIName -Headers $Headers
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })
}
