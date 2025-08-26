function Get-CIPPAlertOneDriveQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        [ValidateRange(0, 100)]
        [int]$InputValue = 90
    )

    try {
        $Usage = New-GraphGetRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application/json&`$top=999" -AsApp $true
        if (!$Usage) {
            return
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-AlertMessage -tenant $($TenantFilter) -message "OneDrive quota Alert: Unable to get OneDrive usage: Error occurred: $ErrorMessage"
        return
    }

    #Check if the OneDrive quota is over the threshold
    $OverQuota = $Usage | ForEach-Object {
        if ($_.StorageUsedInBytes -eq 0 -or $_.storageAllocatedInBytes -eq 0) { return }
        try {
            $UsagePercent = [math]::Round(($_.storageUsedInBytes / $_.storageAllocatedInBytes) * 100)
        } catch { $UsagePercent = 100 }

        if ($UsagePercent -gt $InputValue) {
            $GBLeft = [math]::Round(($_.storageAllocatedInBytes - $_.storageUsedInBytes) / 1GB)
            "$($_.ownerPrincipalName): OneDrive is $UsagePercent% full. OneDrive has $($GBLeft)GB storage left"
        }

    }

    #If the quota is over the threshold, send an alert
    if ($OverQuota) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $OverQuota
    }
}
