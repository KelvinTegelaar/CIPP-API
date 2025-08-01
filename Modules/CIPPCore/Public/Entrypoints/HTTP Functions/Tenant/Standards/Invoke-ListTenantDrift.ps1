using namespace System.Net

function Invoke-ListTenantDrift {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    try {
        # Use the new Get-CIPPTenantAlignment function to get alignment data
        if ($Request.Query.TenantFilter) {
            $TenantFilter = $Request.Query.TenantFilter
            $Results = Get-CIPPDrift -TenantFilter $TenantFilter
        } else {
            $Tenants = Get-Tenants
            $Results = $Tenants | ForEach-Object { Get-CIPPDrift -AllTenants -TenantFilter $_.defaultDomainName }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        Write-LogMessage -API $APIName -message "Failed to get tenant alignment data: $($_.Exception.Message)" -sev Error
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to get tenant alignment data: $($_.Exception.Message)" }
            })
    }
}
