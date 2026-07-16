function Resolve-NinjaOneCveScanGroup {
    <#
    .SYNOPSIS
        Resolves the NinjaOne vulnerability scan group used for CVE sync, creating it if it does not exist.
    .DESCRIPTION
        Looks up the CVE sync scan group by name via the NinjaOne API. If the lookup fails, or if no matching
        scan group is found and the subsequent create attempt also fails, logs the error and returns $null so
        the caller can skip CVE sync for this tenant without failing the overall tenant sync.
    .PARAMETER Configuration
        The NinjaOne configuration object. Must expose CveSyncDeviceIdHeader / CveSyncCveIdHeader (both optional).
    .PARAMETER TenantFilter
        The tenant identifier used for logging context.
    .PARAMETER ScanGroupName
        The resolved scan group name to look up or create.
    .PARAMETER NinjaBaseUrl
        The base NinjaOne API URL (e.g. https://instance/api/v2).
    .PARAMETER Token
        The NinjaOne OAuth token object. Must expose access_token.
    .OUTPUTS
        The resolved (existing or newly-created) scan group object, or $null if it could not be resolved.
    #>
    [CmdletBinding()]
    param (
        $Configuration,
        [string]$TenantFilter,
        [string]$ScanGroupName,
        [string]$NinjaBaseUrl,
        $Token
    )

    try {
        $CveScanGroups = Invoke-RestMethod -Method Get -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers @{ Authorization = "Bearer $($Token.access_token)" } -TimeoutSec 30 -ErrorAction Stop
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync skipped — could not look up scan group '$ScanGroupName': $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        return $null
    }

    # Where-Object returns an array when multiple scan groups share the same name; take the
    # first match so callers always receive a single object as documented, not a collection.
    $ResolvedScanGroup = $CveScanGroups | Where-Object { $_.groupName -eq $ScanGroupName } | Select-Object -First 1

    if (-not $ResolvedScanGroup) {
        Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync — scan group '$ScanGroupName' not found, attempting to create it" -sev 'Info'

        try {
            $NewScanGroupBody = @{
                groupName      = $ScanGroupName
                deviceIdHeader = $Configuration.CveSyncDeviceIdHeader ?? 'deviceName'
                cveIdHeader    = $Configuration.CveSyncCveIdHeader ?? 'cveId'
            } | ConvertTo-Json -Depth 5

            $ResolvedScanGroup = Invoke-RestMethod -Method Post -Uri "$NinjaBaseUrl/vulnerability/scan-groups" -Headers @{ Authorization = "Bearer $($Token.access_token)"; 'Content-Type' = 'application/json' } -Body $NewScanGroupBody -TimeoutSec 30 -ErrorAction Stop
            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync — created scan group '$ScanGroupName'" -sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'NinjaOneSync' -tenant $TenantFilter -message "CVE sync skipped — scan group '$ScanGroupName' not found and could not be created: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
            $ResolvedScanGroup = $null
        }
    }

    return $ResolvedScanGroup
}
