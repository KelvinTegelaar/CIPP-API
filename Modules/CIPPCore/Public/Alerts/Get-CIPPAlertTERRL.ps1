function Get-CIPPAlertTERRL {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # Set threshold with fallback to 80%
        $Threshold = if ([string]::IsNullOrWhiteSpace($InputValue)) { 80 } else { [int]$InputValue }

        # Get TERRL status
        $TerrlStatus = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-LimitsEnforcementStatus'

        if ($TerrlStatus) {
            $UsagePercentage = [math]::Round(($TerrlStatus.ObservedValue / $TerrlStatus.Threshold) * 100, 2)

            if ($UsagePercentage -gt $Threshold) {
                $AlertData = [PSCustomObject]@{
                    UsagePercentage    = $UsagePercentage
                    CurrentVolume      = $TerrlStatus.ObservedValue
                    ThresholdLimit     = $TerrlStatus.Threshold
                    EnforcementEnabled = $TerrlStatus.EnforcementEnabled
                    Verdict            = $TerrlStatus.Verdict
                    Message            = 'Tenant is at {0}% of their TERRL limit (using {1} of {2} messages). Tenant Enforcement Status: {3}' -f $UsagePercentage, $TerrlStatus.ObservedValue, $TerrlStatus.Threshold, $TerrlStatus.Verdict
                    Tenant             = $TenantFilter
                }
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get TERRL status for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
