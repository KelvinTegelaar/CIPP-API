function Push-CIPPAlertDepTokenExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    $LastRunTable = Get-CIPPTable -Table AlertLastRun

    try {
        $Filter = "RowKey eq 'DepTokenExpiry' and PartitionKey eq '{0}'" -f $Item.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            try {
                $DepTokens = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $Item.tenant).value
                foreach ($Dep in $DepTokens) {
                    if ($Dep.tokenExpirationDateTime -lt (Get-Date).AddDays(30) -and $Dep.tokenExpirationDateTime -gt (Get-Date).AddDays(-7)) {
                        Write-AlertMessage -tenant $($Item.tenant) -message ('Apple Device Enrollment Program token expiring on {0}' -f $Dep.tokenExpirationDateTime)
                    }
                }
            } catch {}
            $LastRun = @{
                RowKey       = 'DepTokenExpiry'
                PartitionKey = $Item.tenantid
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        Write-AlertMessage -tenant $($Item.tenant) -message "Failed to check Apple Device Enrollment Program token expiry for $($Item.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
