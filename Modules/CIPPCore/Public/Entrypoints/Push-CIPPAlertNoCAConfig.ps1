function Push-CIPPAlertNoCAConfig {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )

    try {
        $CAAvailable = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $QueueItem.Tenant -erroraction stop).serviceplans
        if ('AAD_PREMIUM' -in $CAAvailable.servicePlanName) {
            $CAPolicies = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $QueueItem.Tenant)
            if (!$CAPolicies.id) {
                Write-AlertMessage -tenant $($QueueItem.tenant) -message 'Conditional Access is available, but no policies could be found.'
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Conditional Access Config Alert: Error occurred: $(Get-NormalizedError -message $_.Exception.message)"
    }

}
