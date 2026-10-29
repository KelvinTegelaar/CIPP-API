function Get-CippExtensionDeviceViewModel {
    <#
        .SYNOPSIS
        Turns one Intune device's data into a display-ready model for Get-CippExtensionDeviceBody.

        .DESCRIPTION
        The model holds plain strings, numbers, bools and lists only, never HTML; the renderer encodes every value.
        It holds no sync timestamp, and staleness is a flag rather than a day count, so the rendered body only changes
        when the data does.

        .PARAMETER Policies
        Compliance policy statuses for the device: Name, Status, LastReported and GraceExpiry.

        .PARAMETER RmmLinks
        Links from the matched documentation record's integration cards, each with Label, Tip and Url.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        [Parameter(Mandatory)]$Tenant,
        $Policies,
        [string[]]$Groups,
        [object[]]$RmmLinks,
        [datetime]$AsOf = (Get-Date),
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc,
        [int]$StaleAfterDays = 30,
        [double]$StorageWarnPct = 90,
        [double]$StorageCritPct = 98
    )

    $Inv = [cultureinfo]::InvariantCulture
    $Now = ConvertTo-CippExtensionUiDate $AsOf
    $DatePattern = Get-CippExtensionUiDatePattern $Culture
    # Timestamps are shown in the instance time zone; staleness is worked out in UTC
    $fmtDate = { param($v) $d = ConvertTo-CippExtensionUiDate $v; if ($d) { [TimeZoneInfo]::ConvertTimeFromUtc($d, $TimeZone).ToString($DatePattern, $Culture) } else { '' } }
    $fmtGb = { param([double]$bytes) ([math]::Round($bytes / 1GB, 2)).ToString('#,##0.##', $Culture) }
    $Compliance = { param($State)
        switch -Regex ([string]$State) {
            '^compliant$' { @('Compliant', 'ok') }
            '^noncompliant$' { @('Non-compliant', 'err') }
            '^ingraceperiod$' { @('In grace period', 'warn') }
            '^error$|^conflict$' { @((Get-CippExtensionUiHumanized $State), 'warn') }
            default { @((Get-CippExtensionUiHumanized $State), 'neutral') }
        }
    }
    $Bool = { param($v) if ($null -eq $v -or "$v" -eq '') { '' } elseif ($v -eq $true -or "$v" -eq 'True') { 'Yes' } else { 'No' } }

    $D = $Device
    $Last = ConvertTo-CippExtensionUiDate $D.lastSyncDateTime
    $Days = if ($Last) { [int]($Now.Date - $Last.Date).Days } else { $null }
    $State = & $Compliance $D.complianceState

    $Header = [ordered]@{
        Name            = [string]$D.deviceName
        Compliance      = $State[0]
        ComplianceTone  = $State[1]
        IsNonCompliant  = ([string]$D.complianceState -eq 'noncompliant')
        Os              = [string]$D.operatingSystem
        OsVersion       = [string]$D.osVersion
        UserName        = [string]$D.userDisplayName
        UserPrincipal   = [string]$D.userPrincipalName
        IsStale         = ($null -ne $Days -and $Days -gt $StaleAfterDays)
        StaleAfterDays  = $StaleAfterDays
    }

    $Links = [ordered]@{
        Microsoft = @([ordered]@{ Label = 'Intune'; Tip = 'Open this device in Intune'; Url = "https://intune.microsoft.com/$($Tenant.defaultDomainName)/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($D.id)" })
        Rmm       = @($RmmLinks | Where-Object { $_ } | ForEach-Object { [ordered]@{ Label = [string]$_.Label; Tip = [string]$_.Tip; Url = [string]$_.Url } })
    }

    $Details = [ordered]@{
        Owner           = (Get-CippExtensionUiHumanized $(if ($D.ownerType) { $D.ownerType } else { $D.managedDeviceOwnerType }))
        Enrolled        = (& $fmtDate $D.enrolledDateTime)
        LastSync        = (& $fmtDate $D.lastSyncDateTime)
        ManagementAgent = $(switch ([string]$D.managementAgent) {
                'mdm' { 'MDM' }
                'eas' { 'EAS' }
                'easMdm' { 'EAS/MDM' }
                'configurationManagerClient' { 'Configuration Manager' }
                'configurationManagerClientMdm' { 'Configuration Manager/MDM' }
                'intuneClient' { 'Intune client' }
                'jamf' { 'Jamf' }
                'googleCloudDevicePolicyController' { 'Google Cloud device policy controller' }
                default { Get-CippExtensionUiHumanized $_ }
            })
    }

    $Storage = [ordered]@{ Present = $false }
    $Total = [double]$D.totalStorageSpaceInBytes
    if ($Total -gt 0) {
        $Free = [math]::Max(0.0, [double]$D.freeStorageSpaceInBytes)
        $Used = [math]::Max(0.0, $Total - $Free)
        $Pct = [math]::Round($Used / $Total * 100, 2)
        $Storage = [ordered]@{
            Present       = $true
            UsedText      = (& $fmtGb $Used) + ' GB'
            AllocatedText = (& $fmtGb $Total) + ' GB'
            FreeText      = (& $fmtGb $Free) + ' GB'
            Pct           = $Pct.ToString('0.##', $Inv)
            PctText       = $Pct.ToString('0.##', $Culture) + '%'
            Tone          = $(if ($Pct -ge $StorageCritPct) { 'err' } elseif ($Pct -ge $StorageWarnPct) { 'warn' } else { 'ok' })
        }
    }
    $Hardware = [ordered]@{
        Serial       = [string]$D.serialNumber
        Chassis      = (Get-CippExtensionUiHumanized $D.chassisType)
        Model        = [string]$D.model
        Manufacturer = [string]$D.manufacturer
        Storage      = $Storage
    }

    $Hw = $D.hardwareinformation
    $Enrollment = [ordered]@{
        EnrollmentType    = (Get-CippExtensionUiHumanized $D.deviceEnrollmentType)
        JoinType          = (Get-CippExtensionUiHumanized $D.joinType)
        RegistrationState = (Get-CippExtensionUiHumanized $D.deviceRegistrationState)
        Autopilot         = (& $Bool $D.autopilotEnrolled)
        DeviceGuard       = (Get-CippExtensionUiHumanized $Hw.deviceGuardVirtualizationBasedSecurityHardwareRequirementState)
        Vbs               = (Get-CippExtensionUiHumanized $Hw.deviceGuardVirtualizationBasedSecurityState)
        CredentialGuard   = (Get-CippExtensionUiHumanized $Hw.deviceGuardLocalSystemAuthorityCredentialGuardState)
    }

    $PolicyItems = @(foreach ($P in @($Policies | Where-Object { $_ })) {
            $PState = & $Compliance $P.Status
            [ordered]@{
                Name        = [string]$P.Name
                StateLabel  = $PState[0]
                StateTone   = $PState[1]
                LastReport  = (& $fmtDate $P.LastReported)
                GraceExpiry = (& $fmtDate $P.GraceExpiry)
            }
        })

    [ordered]@{
        Header     = $Header
        Links      = $Links
        Details    = $Details
        Hardware   = $Hardware
        Enrollment = $Enrollment
        Policies   = $PolicyItems
        Groups     = @($Groups | Where-Object { $_ } | Sort-Object -Unique)
    }
}
