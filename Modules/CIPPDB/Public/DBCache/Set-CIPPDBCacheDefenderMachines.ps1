function Set-CIPPDBCacheDefenderMachines {
    <#
    .SYNOPSIS
        Caches Microsoft Defender for Endpoint devices with their antivirus health for a tenant

    .PARAMETER TenantFilter
        The tenant to cache devices for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Defender devices' -sev Debug

        $Scope = 'https://api.securitycenter.microsoft.com/.default'
        $AvModes = @('Active', 'Passive', 'Disabled', 'Other', 'EDR Blocked', 'Passive Audit')
        $AvByMachine = @{}
        $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter -ErrorAction Stop
        $Plan1Only = $Capabilities.MDE_LITE -and -not ($Capabilities.WINDEFATP -or $Capabilities.MDE_SMB)

        if (-not $Plan1Only) {
            New-GraphGetRequest -uri 'https://api.securitycenter.microsoft.com/api/deviceavinfo?$top=10000' -tenantid $TenantFilter -scope $Scope -AsApp $true -Stream | & { process {
                    if (-not $_.machineId) { throw 'Defender returned an antivirus record without a machineId' }
                    $Mode = if ("$($_.avMode)") { $AvModes[[int]$_.avMode] } else { 'Other' }
                    $Refreshed = if ($_.dataRefreshTimestamp) { ([datetime]$_.dataRefreshTimestamp).ToUniversalTime() } else { [datetime]::MinValue }
                    $Known = $AvByMachine[$_.machineId]
                    if ($null -eq $Known -or $Refreshed -gt $Known.Refreshed) {
                        $AvByMachine[$_.machineId] = @{
                            Refreshed             = $Refreshed
                            avMode                = $Mode
                            avSignatureVersion    = $_.avSignatureVersion
                            avSignatureUpdateTime = $_.avSignatureUpdateTime
                            avIsSignatureUpToDate = $_.avIsSignatureUpToDate
                            avEngineVersion       = $_.avEngineVersion
                            avIsEngineUpToDate    = $_.avIsEngineUpToDate
                            avPlatformVersion     = $_.avPlatformVersion
                            avIsPlatformUpToDate  = $_.avIsPlatformUpToDate
                            quickScanResult       = $_.quickScanResult
                            quickScanTime         = $_.quickScanTime
                            fullScanResult        = $_.fullScanResult
                            fullScanTime          = $_.fullScanTime
                        }
                    }
                } }
        }

        $Devices = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        New-GraphGetRequest -uri 'https://api.securitycenter.microsoft.com/api/machines?$top=10000' -tenantid $TenantFilter -scope $Scope -AsApp $true -Stream | & { process {
                if (-not $_.id) { throw 'Defender returned a device without an id' }
                $Av = $AvByMachine[$_.id]
                $Devices[$_.id] = @{
                    id                    = $_.id
                    computerDnsName       = $_.computerDnsName
                    osPlatform            = $_.osPlatform
                    version               = $_.version
                    osBuild               = $_.osBuild
                    osArchitecture        = $_.osArchitecture
                    healthStatus          = $_.healthStatus
                    onboardingStatus      = $_.onboardingStatus
                    riskScore             = $_.riskScore
                    exposureLevel         = $_.exposureLevel
                    deviceValue           = $_.deviceValue
                    firstSeen             = $_.firstSeen
                    lastSeen              = $_.lastSeen
                    lastIpAddress         = $_.lastIpAddress
                    lastExternalIpAddress = $_.lastExternalIpAddress
                    aadDeviceId           = $_.aadDeviceId
                    machineTags           = $_.machineTags
                    rbacGroupName         = $_.rbacGroupName
                    isExcluded            = $_.isExcluded
                    managedBy             = $_.managedBy
                    managedByStatus       = $_.managedByStatus
                    avMode                = $Av.avMode
                    avSignatureVersion    = $Av.avSignatureVersion
                    avSignatureUpdateTime = $Av.avSignatureUpdateTime
                    avIsSignatureUpToDate = $Av.avIsSignatureUpToDate
                    avEngineVersion       = $Av.avEngineVersion
                    avIsEngineUpToDate    = $Av.avIsEngineUpToDate
                    avPlatformVersion     = $Av.avPlatformVersion
                    avIsPlatformUpToDate  = $Av.avIsPlatformUpToDate
                    quickScanResult       = $Av.quickScanResult
                    quickScanTime         = $Av.quickScanTime
                    fullScanResult        = $Av.fullScanResult
                    fullScanTime          = $Av.fullScanTime
                }
            } }
        $AvByMachine = $null

        $Devices.Values | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefenderMachines' -AddCount -ClearOnEmpty:($Devices.Count -eq 0) -ErrorAction Stop

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Devices.Count) Defender devices successfully" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipping Defender device cache - tenant not onboarded to Defender for Endpoint: $($ErrorMessage.NormalizedError)" -sev Debug -LogData $ErrorMessage
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Defender devices: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw
    }
}
