function Push-CIPPAlertSecDefaultsUpsell {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    $LastRunTable = $QueueItem.LastRunTable

    try {
        $Filter = "RowKey eq 'SecDefaultsUpsell' and PartitionKey eq '{0}'" -f $QueueItem.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            try {
                $SecDefaults = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $QueueItem.tenant)
                if ($SecDefaults.isEnabled -eq $false -and $SecDefaults.securityDefaultsUpsell.action -in @('autoEnable', 'autoEnabledNotify')) {
                    Write-AlertMessage -tenant $($QueueItem.tenant) -message ('Security Defaults will be automatically enabled on {0}' -f $SecDefaults.securityDefaultsUpsell.dueDateTime)
                }
            } catch {}
            $LastRun = @{
                RowKey       = 'SecDefaultsUpsell'
                PartitionKey = $QueueItem.tenantid
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        # Error handling
    }
}

