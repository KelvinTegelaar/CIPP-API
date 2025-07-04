using namespace System.Net

function Invoke-AddCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenants = $Request.body.tenantFilter.value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $Results = foreach ($Tenant in $Tenants) {
        try {
            $CAPolicyParams = @{
                replacePattern = $Request.Body.replacename
                Overwrite      = $Request.Body.overwrite
                TenantFilter   = $Tenant
                state          = $Request.Body.NewState
                RawJSON        = $Request.Body.RawJSON
                APIName        = $APIName
                Headers        = $Headers
            }
            New-CIPPCAPolicy @CAPolicyParams

        } catch {
            $_.Exception.Message
            continue
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Results) }
    }
}
