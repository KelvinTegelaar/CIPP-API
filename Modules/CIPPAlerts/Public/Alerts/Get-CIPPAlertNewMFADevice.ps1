function Get-CIPPAlertNewMFADevice {
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
        # Single-input alerts pass a scalar; accept an object with .InputValue too
        $RawPatterns = if ($InputValue -is [string] -or $null -eq $InputValue) { $InputValue } else { $InputValue.InputValue }
        $UpnPatterns = if ("$RawPatterns".Trim()) {
            $ExpandedPatterns = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text ([string]$RawPatterns)
            @($ExpandedPatterns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else { @() }

        $OneHourAgo = (Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')

        $AuditLogs = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $OneHourAgo and (activityDisplayName eq 'User registered security info' or activityDisplayName eq 'User deleted security info')" -tenantid $TenantFilter
        $AlertData = foreach ($Log in $AuditLogs) {
            if ($Log.activityDisplayName -eq 'User registered security info') {
                $User = $Log.targetResources[0].userPrincipalName
                if (-not $User) { $User = $Log.initiatedBy.user.userPrincipalName }

                if ($UpnPatterns.Count -gt 0) {
                    $Matched = $false
                    if ($User) {
                        foreach ($Pattern in $UpnPatterns) {
                            if ($User -like $Pattern) { $Matched = $true; break }
                        }
                    }
                    if (-not $Matched) { continue }
                }

                $IPAddress = $Log.initiatedBy.user.ipAddress
                $LocationData = $null
                if (-not [string]::IsNullOrEmpty($IPAddress) -and $IPAddress -notmatch '[X]+') {
                    try {
                        $LocationData = Get-CIPPGeoIPLocation -IP $IPAddress
                    } catch {
                        Write-Information "Could not enrich MFA audit IP ${IPAddress}: $($_.Exception.Message)"
                    }
                }

                [PSCustomObject]@{
                    Message           = "New MFA method registered: $User"
                    User              = $User
                    DisplayName       = $Log.targetResources[0].displayName
                    Activity          = $Log.activityDisplayName
                    ActivityTime      = $Log.activityDateTime
                    Tenant            = $TenantFilter
                    IpAddress         = $IPAddress
                    CountryOrRegion   = if ($LocationData) { $LocationData.countryCode } else { $null }
                    City              = if ($LocationData) { $LocationData.city } else { $null }
                    Proxy             = if ($LocationData) { $LocationData.proxy } else { $null }
                    Hosting           = if ($LocationData) { $LocationData.hosting } else { $null }
                    ASN               = if ($LocationData) { $LocationData.asname } else { $null }
                    GeoLocationInfo   = if ($LocationData) { ($LocationData | ConvertTo-Json -Depth 10 -Compress) } else { $null }
                }
            }
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check for new MFA devices for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
