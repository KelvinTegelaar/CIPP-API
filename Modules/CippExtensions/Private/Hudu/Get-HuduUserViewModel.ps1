function Get-HuduUserViewModel {
    <#
        .SYNOPSIS
        Turns one user's data into a display-ready model for Get-HuduUserBody.

        .DESCRIPTION
        The model holds plain strings, numbers, bools and lists only, never HTML; the renderer encodes every value.
        It holds no sync timestamp, so the rendered body only changes when the data does.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)]$Tenant,
        $Groups,
        $Policies,
        $MailSettings,
        $Devices,
        $OneDrive,
        [string[]]$LicenseNames,
        $AssignedNameMap,
        [string]$CippUrl,
        [bool]$EnableCIPP = $true,
        [object[]]$PsaLinks,
        [datetime]$AsOf = (Get-Date),
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [TimeZoneInfo]$TimeZone = [TimeZoneInfo]::Utc,
        [int]$StaleAfterDays = 30,
        [double]$StorageWarnPct = 90,
        [double]$StorageCritPct = 98
    )

    $Inv = [cultureinfo]::InvariantCulture
    $Now = ConvertTo-HuduUiDate $AsOf
    $Domain = $Tenant.defaultDomainName
    $Dot = [string][char]0x00B7
    $DatePattern = Get-HuduUiDatePattern $Culture
    # Timestamps are shown in the instance time zone; date-only values are not converted. Staleness is worked out in UTC.
    $fmtDate = {
        param($v)
        if ($v -is [string] -and $v -match '^\d{4}-\d{2}-\d{2}$') { return ([datetime]::ParseExact($v, 'yyyy-MM-dd', $Inv)).ToString($DatePattern, $Culture) }
        $d = ConvertTo-HuduUiDate $v
        if ($d) { [TimeZoneInfo]::ConvertTimeFromUtc($d, $TimeZone).ToString($DatePattern, $Culture) } else { '' }
    }
    $fmtGb = { param([double]$bytes) ([math]::Round($bytes / 1GB, 2)).ToString('#,##0.##', $Culture) }
    $toneFor = { param([double]$p) if ($p -ge $StorageCritPct) { 'err' } elseif ($p -ge $StorageWarnPct) { 'warn' } else { 'ok' } }

    # Header
    $Words = @(([string]$User.displayName -split '\s+') | Where-Object { $_ })
    $Initials = if ($Words.Count -ge 2) { "$($Words[0][0])$($Words[1][0])".ToUpper() } elseif ($Words.Count -eq 1) { $Words[0].Substring(0, [math]::Min(2, $Words[0].Length)).ToUpper() } else { '?' }
    $Header = [ordered]@{
        DisplayName  = [string]$User.displayName
        Initials     = $Initials
        Upn          = [string]$User.userPrincipalName
        JobTitle     = [string]$User.jobTitle
        IsEnabled    = [bool]$User.accountEnabled
        EnabledLabel = $(if ($User.accountEnabled) { 'Enabled' } else { 'Disabled' })
        EnabledTone  = $(if ($User.accountEnabled) { 'ok' } else { 'err' })
        EnabledTip   = "Account enabled: $($User.accountEnabled)"
    }

    # Links
    $Uid = $User.id
    $MsLinks = @(
        [ordered]@{ Label = 'Entra ID'; Tip = 'Open Entra ID profile in a new tab'; Url = "https://entra.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$Uid" }
        [ordered]@{ Label = 'Sign-ins'; Tip = 'Open sign-in logs in a new tab'; Url = "https://entra.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/SignIns/userId/$Uid" }
        [ordered]@{ Label = 'Teams Admin'; Tip = 'Open Teams admin center in a new tab'; Url = "https://admin.teams.microsoft.com/users/$Uid/account?delegatedOrg=$Domain" }
        [ordered]@{ Label = 'Intune (User)'; Tip = 'Open Intune user profile in a new tab'; Url = "https://intune.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$Uid" }
        [ordered]@{ Label = 'Intune (Devices)'; Tip = "Open the user's Intune devices in a new tab"; Url = "https://intune.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Devices/userId/$Uid" }
    )
    $CippLinks = @()
    if ($EnableCIPP) {
        $CippLinks = @(
            [ordered]@{ Label = 'View user'; Tip = 'View this user in CIPP'; Url = "$CippUrl/identity/administration/users/user?tenantFilter=$Domain&userId=$Uid" }
            [ordered]@{ Label = 'Edit user'; Tip = 'Edit this user in CIPP'; Url = "$CippUrl/identity/administration/users/user/edit?tenantFilter=$Domain&userId=$Uid" }
            [ordered]@{ Label = 'BEC tool'; Tip = 'Open the BEC investigation tool in CIPP'; Url = "$CippUrl/identity/administration/bec/case?tenantFilter=$Domain&userId=$Uid" }
        )
    }
    $Psa = @($PsaLinks | Where-Object { $_ } | ForEach-Object { [ordered]@{ Label = [string]$_.Label; Tip = [string]$_.Tip; Url = [string]$_.Url } })
    $Links = [ordered]@{ Microsoft = $MsLinks; Cipp = $CippLinks; Psa = $Psa }

    # Contact
    $Contact = [ordered]@{
        BusinessPhone = (@($User.businessPhones) -join ', ')
        Mobile        = [string]$User.mobilePhone
        Office        = [string]$User.officeLocation
        UserId        = [string]$User.id
    }

    # Mailbox
    $Mailbox = [ordered]@{ Present = $false }
    $Access = @()
    $MailSettingsVm = [ordered]@{ Present = $false }
    if ($MailSettings) {
        if ($null -ne $MailSettings.StorageUsedInBytes -or $null -ne $MailSettings.ProhibitSendReceiveQuota) {
            $Used = [double]$MailSettings.StorageUsedInBytes
            $Alloc = [double]$MailSettings.ProhibitSendReceiveQuota
            $Pct = if ($Alloc -gt 0) { [math]::Round($Used / $Alloc * 100, 2) } else { 0.0 }
            $Mailbox = [ordered]@{
                Present              = $true
                UsedText             = (& $fmtGb $Used) + ' GB'
                AllocatedText        = (& $fmtGb $Alloc) + ' GB'
                Pct                  = $Pct.ToString('0.##', $Inv)
                PctText              = $Pct.ToString('0.##', $Culture) + '%'
                Tone                 = (& $toneFor $Pct)
                Items                = ([double]$MailSettings.ItemCount).ToString('N0', $Culture)
                SendBlockedAt        = (& $fmtGb ([double]$MailSettings.ProhibitSendQuota)) + ' GB'
                SendReceiveBlockedAt = (& $fmtGb $Alloc) + ' GB'
            }
        }
        $Owner = [string]$User.userPrincipalName
        $Access = @($MailSettings.Permissions | Where-Object { $_ } | Group-Object User | ForEach-Object {
                [ordered]@{
                    Who     = [string]$_.Name
                    IsOwner = ($_.Name -eq $Owner)
                    Rights  = @($_.Group.AccessRights | ForEach-Object { $_ -split ',\s*' } | Where-Object { $_ } | Select-Object -Unique | ForEach-Object {
                            switch ($_) { 'FullAccess' { 'Full access' } 'SendAs' { 'Send as' } 'SendOnBehalf' { 'Send on behalf' } default { Get-HuduUiHumanized $_ } }
                        })
                }
            } | Sort-Object { $_.IsOwner }, { $_.Who })
        $AllProtocols = @(
            [ordered]@{ Name = 'EWS'; On = [bool]$MailSettings.EWSEnabled }
            [ordered]@{ Name = 'MAPI'; On = [bool]$MailSettings.MailboxMAPIEnabled }
            [ordered]@{ Name = 'OWA'; On = [bool]$MailSettings.MailboxOWAEnabled }
            [ordered]@{ Name = 'ActiveSync'; On = [bool]$MailSettings.MailboxActiveSyncEnabled }
            [ordered]@{ Name = 'IMAP'; On = [bool]$MailSettings.MailboxImapEnabled }
            [ordered]@{ Name = 'POP'; On = [bool]$MailSettings.MailboxPopEnabled }
        )
        $FwdActive = -not [string]::IsNullOrWhiteSpace([string]$MailSettings.ForwardingAddress)
        $MailSettingsVm = [ordered]@{
            Present        = $true
            Protocols      = @($AllProtocols | Where-Object { $_.On }; $AllProtocols | Where-Object { -not $_.On })
            Forwarding     = [ordered]@{
                IsActive = $FwdActive
                Text     = $(if ($FwdActive) { [string]$MailSettings.ForwardingAddress } else { 'None' })
                Note     = $(if ($FwdActive) { if ($MailSettings.ForwardAndDeliver) { 'also delivered to the mailbox' } else { 'no copy kept in the mailbox' } } else { 'forward and deliver off' })
            }
            LitigationHold = $(if ($MailSettings.LitiationHold) { 'On' } else { 'Off' })
            Hidden         = $(if ($MailSettings.HiddenFromAddressLists) { 'Yes' } else { 'No' })
        }
    }

    # OneDrive
    $Od = [ordered]@{ Present = $false }
    if ($OneDrive) {
        $OUsed = [double]$OneDrive.storageUsedInBytes
        $OAlloc = [double]$OneDrive.storageAllocatedInBytes
        $OPct = if ($OAlloc -gt 0) { [math]::Round($OUsed / $OAlloc * 100, 2) } else { 0.0 }
        $OTone = & $toneFor $OPct
        $Od = [ordered]@{
            Present       = $true
            UsedText      = (& $fmtGb $OUsed) + ' GB'
            AllocatedText = (& $fmtGb $OAlloc) + ' GB'
            Pct           = $OPct.ToString('0.##', $Inv)
            PctText       = $OPct.ToString('0.##', $Culture) + '%'
            Tone          = $OTone
            HasFlag       = ($OTone -ne 'ok')
            FlagText      = $(if ($OTone -eq 'err') { 'Nearly full' } else { "Over $([math]::Round($StorageWarnPct))% used" })
            FlagTip       = $(if ($OTone -eq 'err') { "Usage is above $([math]::Round($StorageCritPct))%" } else { "Usage is above $([math]::Round($StorageWarnPct))%" })
            Files         = ([double]$OneDrive.fileCount).ToString('N0', $Culture)
            ActiveFiles   = ([double]$OneDrive.activeFileCount).ToString('N0', $Culture)
            LastActivity  = (& $fmtDate $OneDrive.lastActivityDate)
            SiteUrl       = [string]$OneDrive.siteUrl
            IsDeleted     = [bool]$OneDrive.isDeleted
        }
    }

    # Licenses and aliases; the primary SMTP address and onmicrosoft.com addresses are left out as before
    $Lic = @($LicenseNames | Where-Object { $_ } | Sort-Object -Unique)
    $Smtp = @($User.proxyAddresses | Where-Object { $_ -cnotmatch 'SMTP' -and $_ -notmatch '\.onmicrosoft\.com' -and $_ -notmatch '^x500:' } | ForEach-Object { $_ -replace '^smtp:', '' })
    $X500 = @($User.proxyAddresses | Where-Object { $_ -match '^x500:' })
    $Aliases = [ordered]@{
        Addresses = $Smtp
        X500      = $X500
        Present   = ($Smtp.Count + $X500.Count) -gt 0
        Summary   = (@("$($Smtp.Count) $(if ($Smtp.Count -eq 1) { 'address' } else { 'addresses' })"; $(if ($X500.Count) { "$($X500.Count) X500" })) -join ', ')
    }

    # Service plans, one entry per service with the most recent assignment date
    $PlanRows = foreach ($P in @($User.assignedplans | Where-Object { $_.capabilityStatus -eq 'Enabled' } | Select-Object service, assignedDateTime -Unique)) {
        $Name = $AssignedNameMap.($P.service)
        if ($Name) { [pscustomobject]@{ Name = [string]$Name; Date = ConvertTo-HuduUiDate $P.assignedDateTime } }
    }
    $PlanItems = @($PlanRows | Group-Object Name | Sort-Object Name | ForEach-Object {
            $Latest = ($_.Group.Date | Sort-Object -Descending | Select-Object -First 1)
            [ordered]@{
                Name       = $_.Name
                Count      = $_.Count
                CountLabel = $(if ($_.Count -gt 1) { "$([char]0x00D7)$($_.Count)" } else { '' })
                Title      = $(if ($_.Count -gt 1) { "$($_.Name): $($_.Count) assignments, most recent $(& $fmtDate $Latest)" } else { "$($_.Name): assigned $(& $fmtDate $Latest)" })
            }
        })
    $Plans = [ordered]@{ Items = $PlanItems; AssignmentCount = [int]($PlanItems | Measure-Object Count -Sum).Sum }

    # Conditional Access
    $AppNames = @{ all = 'All'; other = 'Other'; exchangeActiveSync = 'Exchange ActiveSync'; browser = 'Browser'; mobileAppsAndDesktopClients = 'Mobile and desktop apps' }
    $CaAll = @(foreach ($Pol in @($Policies | Where-Object { $_ })) {
            $State = switch -Regex ([string]$Pol.state) {
                '^enabled$' { @('On', 'ok', 0) }
                '^enabledForReportingButNotEnforced$' { @('Report-only', 'info', 1) }
                '^disabled$' { @('Off', 'neutral', 2) }
                default { @((Get-HuduUiHumanized $Pol.state), 'neutral', 3) }
            }
            $Apps = (([string]$Pol.clientAppTypes -split ',\s*') | Where-Object { $_ } | ForEach-Object { if ($AppNames.ContainsKey($_)) { $AppNames[$_] } else { Get-HuduUiHumanized $_ } }) -join ', '
            $Conds = [System.Collections.Generic.List[string]]::new()
            if ($Pol.userRiskLevels -and $Pol.userRiskLevels -ne 'None') { $Conds.Add("User risk: $($Pol.userRiskLevels)") }
            if ($Pol.signInRiskLevels -and $Pol.signInRiskLevels -ne 'None') { $Conds.Add("Sign-in risk: $($Pol.signInRiskLevels)") }
            if ($Pol.signInFrequency -and $Pol.signInFrequency -notin @('Not configured', 'None')) { $Conds.Add("Sign-in frequency: $($Pol.signInFrequency)") }
            if ($Pol.authenticationStrength -and $Pol.authenticationStrength -ne 'None') { $Conds.Add("grant $(([string]$Pol.authenticationStrength).ToLower())") }
            [ordered]@{
                Name           = [string]$Pol.displayName
                StateLabel     = $State[0]
                StateTone      = $State[1]
                Rank           = $State[2]
                ClientApps     = $Apps
                ConditionsText = ($Conds -join ', ')
            }
        })
    $CaOn = @($CaAll | Where-Object { $_.Rank -eq 0 })
    $CaRo = @($CaAll | Where-Object { $_.Rank -eq 1 })
    $CaOff = @($CaAll | Where-Object { $_.Rank -ge 2 })
    $CA = [ordered]@{
        Items           = @($CaOn; $CaRo; $CaOff)
        ReportOnlyCount = $CaRo.Count
        Summary         = (@($(if ($CaOn.Count) { "$($CaOn.Count) on" }); $(if ($CaRo.Count) { "$($CaRo.Count) report-only" }); $(if ($CaOff.Count) { "$($CaOff.Count) off" })) -join " $Dot ")
    }

    # Devices. Staleness is a flag rather than a day count so the body does not change every day.
    $DevItems = @(foreach ($D in @($Devices | Where-Object { $_ } | Sort-Object { ConvertTo-HuduUiDate $_.lastSyncDateTime } -Descending)) {
            $Last = ConvertTo-HuduUiDate $D.lastSyncDateTime
            $Days = if ($Last) { [int]($Now.Date - $Last.Date).Days } else { $null }
            $Comp = switch -Regex ([string]$D.complianceState) {
                '^compliant$' { @('Compliant', 'ok') }
                '^noncompliant$' { @('Non-compliant', 'err') }
                '^ingraceperiod$' { @('In grace period', 'warn') }
                '^error$|^conflict$' { @((Get-HuduUiHumanized $D.complianceState), 'warn') }
                default { @((Get-HuduUiHumanized $D.complianceState), 'neutral') }
            }
            [ordered]@{
                Name           = [string]$D.deviceName
                Url            = "https://intune.microsoft.com/$Domain/#blade/Microsoft_Intune_Devices/DeviceSettingsBlade/overview/mdmDeviceId/$($D.id)"
                Tip            = "Open $($D.deviceName) in Intune"
                Detail         = (@($D.model, $D.manufacturer) | Where-Object { $_ }) -join ', '
                Compliance     = $Comp[0]
                Tone           = $Comp[1]
                IsCompliant    = ($Comp[1] -eq 'ok')
                IsNonCompliant = ([string]$D.complianceState -eq 'noncompliant')
                Owner          = (Get-HuduUiHumanized $D.managedDeviceOwnerType)
                Os             = [string]$D.operatingSystem
                OsVersion      = [string]$D.osVersion
                LastSync       = (& $fmtDate $Last)
                Enrolled       = (& $fmtDate $D.enrolledDateTime)
                IsStale        = ($null -ne $Days -and $Days -gt $StaleAfterDays)
                StaleText      = "Over $StaleAfterDays days"
                StaleTip       = "No sync in over $StaleAfterDays days"
            }
        })
    $Dev = [ordered]@{
        Items          = $DevItems
        StaleAfterDays = $StaleAfterDays
        Summary        = "$(@($DevItems | Where-Object { $_.IsCompliant }).Count) compliant $Dot $(@($DevItems | Where-Object { $_.IsNonCompliant }).Count) non-compliant"
    }

    # Groups by type, each type de-duplicated
    $Cats = [ordered]@{
        m365 = @{ Title = 'Microsoft 365 groups'; Short = 'Microsoft 365'; Color = '#f77f00'; Rows = [System.Collections.Generic.List[string]]::new() }
        sec  = @{ Title = 'Security groups'; Short = 'security'; Color = '#005c63'; Rows = [System.Collections.Generic.List[string]]::new() }
        dist = @{ Title = 'Distribution lists'; Short = 'distribution'; Color = '#3e5c66'; Rows = [System.Collections.Generic.List[string]]::new() }
        mes  = @{ Title = 'Mail-enabled security groups'; Short = 'mail-enabled security'; Color = '#8a8f98'; Rows = [System.Collections.Generic.List[string]]::new() }
    }
    $GroupList = @($Groups | Where-Object { $_ })
    foreach ($G in $GroupList) {
        $Key = if ([string]$G.'Group Types' -match 'Unified') { 'm365' } elseif ($G.'Mail Enabled' -and $G.'Security Group') { 'mes' } elseif ($G.'Mail Enabled') { 'dist' } else { 'sec' }
        $Cats[$Key].Rows.Add([string]$G.'Display Name')
    }
    $CatItems = @(foreach ($C in $Cats.Values) {
            if ($C.Rows.Count -gt 0) {
                [ordered]@{
                    Title = $C.Title; Short = $C.Short; Color = $C.Color; Count = $C.Rows.Count
                    Pct   = ([math]::Round($C.Rows.Count / $GroupList.Count * 100, 2)).ToString('0.##', $Inv)
                    Items = @($C.Rows | Group-Object | Sort-Object Name | ForEach-Object {
                            [ordered]@{ Name = $_.Name; CountLabel = $(if ($_.Count -gt 1) { "$([char]0x00D7)$($_.Count)" } else { '' }) }
                        })
                }
            }
        })
    $Grp = [ordered]@{
        Total      = $GroupList.Count
        Categories = $CatItems
        Summary    = ($CatItems | ForEach-Object { "$($_.Count) $($_.Short)" }) -join " $Dot "
    }

    [ordered]@{
        Header       = $Header
        Links        = $Links
        Contact      = $Contact
        Mailbox      = $Mailbox
        MailAccess   = $Access
        MailSettings = $MailSettingsVm
        OneDrive     = $Od
        Licenses     = $Lic
        Aliases      = $Aliases
        Plans        = $Plans
        CA           = $CA
        Devices      = $Dev
        Groups       = $Grp
    }
}
