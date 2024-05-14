function Get-CIPPAlertNoCAConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )

    try {
        $CAAvailable = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter -erroraction stop).serviceplans
        if ('AAD_PREMIUM' -in $CAAvailable.servicePlanName) {
            $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $TenantFilter)
            if (!$CAPolicies.id) {
                $AlertData = 'Conditional Access is available, but no policies could be found.'
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

            }
        }

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Conditional Access Config Alert: Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }

}
