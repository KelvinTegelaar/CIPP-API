BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Documentation/*.ps1", "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }

    $script:AsOf = [datetime]::new(2026, 10, 20, 12, 0, 0, [System.DateTimeKind]::Utc)

    function New-TestModelParams {
        param([switch]$Minimal)
        $User = [PSCustomObject]@{
            id = '00000000-0000-4000-8000-000000000001'; displayName = 'Ada Lovelace'; userPrincipalName = 'ada@fabrikam.example'
            accountEnabled = $true; jobTitle = 'Engineer'; mobilePhone = '555-0100'; businessPhones = @('555-0101'); officeLocation = 'Lab'
            proxyAddresses = @('SMTP:ada@fabrikam.example', 'smtp:ada.l@fabrikam.example', 'smtp:ada@fabrikam.onmicrosoft.com', 'x500:/o=Test/cn=ada')
            assignedPlans = @(
                [PSCustomObject]@{ service = 'exchange'; capabilityStatus = 'Enabled'; assignedDateTime = '2026-01-02T00:00:00Z' }
                [PSCustomObject]@{ service = 'exchange'; capabilityStatus = 'Enabled'; assignedDateTime = '2026-03-04T00:00:00Z' }
                [PSCustomObject]@{ service = 'unmapped'; capabilityStatus = 'Enabled'; assignedDateTime = '2026-03-04T00:00:00Z' }
            )
        }
        $Tenant = [PSCustomObject]@{ defaultDomainName = 'fabrikam.example' }
        if ($Minimal) {
            return @{ User = $User; Tenant = $Tenant; EnableCIPP = $false; AsOf = $script:AsOf }
        }
        @{
            User            = $User
            Tenant          = $Tenant
            Groups          = @(
                [PSCustomObject]@{ 'Display Name' = 'Team Alpha'; 'Mail Enabled' = $true; 'Security Group' = $false; 'Group Types' = 'Unified' }
                [PSCustomObject]@{ 'Display Name' = 'Badge Readers'; 'Mail Enabled' = $false; 'Security Group' = $true; 'Group Types' = '' }
            )
            Policies        = @(
                [PSCustomObject]@{ displayName = 'Require MFA'; state = 'enabled'; clientAppTypes = 'all'; authenticationStrength = 'None'; signInFrequency = 'Not configured'; userRiskLevels = 'None'; signInRiskLevels = 'high' }
            )
            MailSettings    = [PSCustomObject]@{
                ForwardAndDeliver = $false; ForwardingAddress = ''; LitiationHold = $false; HiddenFromAddressLists = $false
                EWSEnabled = $true; MailboxMAPIEnabled = $true; MailboxOWAEnabled = $true; MailboxImapEnabled = $false; MailboxPopEnabled = $false; MailboxActiveSyncEnabled = $true
                Permissions = @([PSCustomObject]@{ User = 'grace@fabrikam.example'; AccessRights = 'FullAccess' })
                ProhibitSendQuota = 99GB; ProhibitSendReceiveQuota = 100GB; ItemCount = 1234; StorageUsedInBytes = 20GB
            }
            Devices         = @(
                [PSCustomObject]@{ id = 'dev-1'; deviceName = 'LAPTOP-1'; complianceState = 'compliant'; managedDeviceOwnerType = 'company'; operatingSystem = 'Windows'; osVersion = '10.0'; lastSyncDateTime = '2026-10-19T00:00:00Z'; enrolledDateTime = '2025-01-01T00:00:00Z'; model = 'Model X'; manufacturer = 'Contoso' }
            )
            OneDrive        = [PSCustomObject]@{ siteUrl = 'https://fabrikam-my.example/personal/ada'; storageUsedInBytes = 10GB; storageAllocatedInBytes = 1024GB; fileCount = 10; activeFileCount = 2; lastActivityDate = '2026-10-18'; isDeleted = $false }
            LicenseNames    = @('Business Premium')
            AssignedNameMap = @{ exchange = 'Exchange Online' }
            CippUrl         = 'https://cipp.example'
            EnableCIPP      = $true
            PsaLinks        = @(@{ Label = 'Halo PSA'; Tip = 'Open in Halo PSA'; Url = 'https://psa.example/user/7' })
            AsOf            = $script:AsOf
        }
    }

    function Get-TestAttention {
        param([hashtable]$Params)
        @(Get-CippExtensionUserAttentionItems -Model (Get-CippExtensionUserViewModel @Params))
    }
}

Describe 'Get-CippExtensionUserBody' {
    It 'renders every section for a full model' {
        $Params = New-TestModelParams
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf
        foreach ($Heading in 'Contact', 'Mailbox', 'OneDrive', 'Mailbox access', 'Mailbox settings', 'Licenses', 'Conditional Access', 'Intune devices', 'Groups', 'Service plans') {
            $Body | Should -Match ">$Heading( <span|</span></h3>)"
        }
        foreach ($Text in 'Ada Lovelace', 'Aliases', 'ada.l@fabrikam.example', 'x500:/o=Test/cn=ada', 'Team Alpha', 'Badge Readers', 'Require MFA', 'LAPTOP-1', 'Exchange Online', 'grace@fabrikam.example', 'Business Premium', 'Halo PSA', 'BEC tool', 'Synced 20 Oct 2026 12:00 UTC', 'Exchange Online: 2 assignments, most recent 4 Mar 2026') {
            $Body | Should -Match ([regex]::Escape($Text))
        }
        $Body | Should -Not -Match 'Needs attention'
        $Body | Should -Not -Match 'ada@fabrikam\.onmicrosoft\.com'
        $Body | Should -Not -Match 'unmapped'
    }

    It 'leaves out sections that have no data' {
        $Params = New-TestModelParams -Minimal
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params)
        $Body | Should -Match '>Contact</span></h3>'
        foreach ($Heading in 'Mailbox', 'OneDrive', 'Mailbox access', 'Mailbox settings', 'Conditional Access', 'Intune devices', 'Groups', 'Needs attention') {
            $Body | Should -Not -Match ">$Heading( <span|</h3>|<)"
        }
        $Body | Should -Not -Match 'cipp\.example|>CIPP<|>PSA<'
        # aliases exist on the minimal user, so the Licenses card is still shown for them
        $Body | Should -Match 'Aliases'
    }

    It 'resets the borders Hudu puts on rich text tables' {
        $Params = New-TestModelParams
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params)
        $Tags = [regex]::Matches($Body, '<(table|th|td) style="[^"]*"')
        $Tags.Count | Should -BeGreaterThan 0
        foreach ($Tag in $Tags) { $Tag.Value | Should -Match 'border(-width)?:0' }
    }

    It 'uses nothing the Hudu sanitizer strips' {
        $Params = New-TestModelParams
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Not -Match 'gap:'
        $Body | Should -Not -Match '<svg'
        $Body | Should -Not -Match 'aria-hidden'
        $Body | Should -Not -Match '<details'
    }

    It 'uses no layout CSS that Hudu or its mobile app drops' {
        $Params = New-TestModelParams
        $Params.Policies[0].state = 'enabledForReportingButNotEnforced'
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Match 'Needs attention'
        $Body | Should -Not -Match 'display:(inline-)?flex|justify-content|float:|gap:'
    }

    It 'uses the CIPP brand without orange text' {
        $Params = New-TestModelParams
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Match '^<div style="overflow:hidden"><div style="border:1px solid rgba\(128,128,128,.3\);border-top:3px solid #f77f00;'
        $Body | Should -Match 'background:rgba\(247,127,0,.12\);[^"]*"><i class="fas fa-envelope" style="color:#f77f00;font-size:12px"></i></span><span style="vertical-align:middle">Mailbox</span></h3>'
        $Body | Should -Match 'width:20%;background:#f77f00'
        $Body | Should -Match 'width:50%;background:#f77f00'
        $Body | Should -Not -Match 'border-radius:1[02]px'
        foreach ($Use in [regex]::Matches($Body, '(?<![-\w])color:#f77f00')) {
            $Body.Substring(0, $Use.Index) | Should -Match '<i class="[^"]*" style="[^"]*$'
        }
    }

    It 'encodes every data value, including attributes' {
        $Evil = '<script>alert(1)</script>"x'
        $Params = New-TestModelParams
        $Params.User.displayName = $Evil
        $Params.User.jobTitle = $Evil
        $Params.Groups[0].'Display Name' = $Evil
        $Params.Policies[0].displayName = $Evil
        $Params.Devices[0].deviceName = $Evil
        $Params.LicenseNames = @($Evil)
        $Params.PsaLinks = @(@{ Label = $Evil; Tip = $Evil; Url = 'https://psa.example/u" onmouseover="alert(1)' })
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf

        $Body | Should -Not -Match '<script'
        $Body | Should -Not -Match '"x'
        $Body | Should -Not -Match '" onmouseover='
        $Body | Should -Match ([regex]::Escape('&lt;script&gt;alert(1)&lt;/script&gt;&quot;x'))
        $Body | Should -Match ([regex]::Escape('href="https://psa.example/u&quot; onmouseover=&quot;alert(1)"'))
    }

    It 'hashes the same body whatever the sync time, and only adds the timestamp when asked' {
        $Params = New-TestModelParams
        $First = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params)
        $Params.AsOf = $script:AsOf.AddDays(1)
        $Second = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params)
        $Second | Should -BeExactly $First
        $First | Should -Not -Match 'Synced'

        $Model = Get-CippExtensionUserViewModel @Params
        $A = Get-CippExtensionUserBody -Model $Model -SyncedAt $script:AsOf
        $B = Get-CippExtensionUserBody -Model $Model -SyncedAt $script:AsOf.AddHours(5)
        $A | Should -Not -BeExactly $B
        $A | Should -Match 'Synced'
    }
}

Describe 'Get-CippExtensionUserAttentionItems' {
    It 'returns nothing when nothing applies' {
        Get-TestAttention (New-TestModelParams) | Should -BeNullOrEmpty
    }

    It 'flags OneDrive at 90% full and not below' {
        $Params = New-TestModelParams
        $Params.OneDrive.storageUsedInBytes = 900; $Params.OneDrive.storageAllocatedInBytes = 1000
        Get-TestAttention $Params | Should -Match '^OneDrive is \*\*90%\*\* full'
        $Params.OneDrive.storageUsedInBytes = 899
        Get-TestAttention $Params | Should -BeNullOrEmpty
    }

    It 'flags the mailbox at 90% full and not below' {
        $Params = New-TestModelParams
        $Params.MailSettings.StorageUsedInBytes = 90GB
        Get-TestAttention $Params | Should -Match '^Mailbox is \*\*90%\*\* full'
        $Params.MailSettings.StorageUsedInBytes = 89.9GB
        Get-TestAttention $Params | Should -BeNullOrEmpty
    }

    It 'flags non-compliant devices only' {
        $Params = New-TestModelParams
        $Params.Devices[0].complianceState = 'inGracePeriod'
        Get-TestAttention $Params | Should -BeNullOrEmpty
        $Params.Devices[0].complianceState = 'noncompliant'
        Get-TestAttention $Params | Should -Be '**1 device** is non-compliant: LAPTOP-1'
    }

    It 'flags devices not synced in more than 30 days' {
        $Params = New-TestModelParams
        $Params.Devices[0].lastSyncDateTime = $script:AsOf.AddDays(-30).ToString('o')
        Get-TestAttention $Params | Should -BeNullOrEmpty
        $Params.Devices[0].lastSyncDateTime = $script:AsOf.AddDays(-31).ToString('o')
        Get-TestAttention $Params | Should -Be '**1 device** not synced in over 30 days: LAPTOP-1'
    }

    It 'flags report-only Conditional Access policies' {
        $Params = New-TestModelParams
        $Params.Policies[0].state = 'enabledForReportingButNotEnforced'
        Get-TestAttention $Params | Should -Be '**1 Conditional Access policy** is report-only'
    }

    It 'flags mailbox forwarding' {
        $Params = New-TestModelParams
        $Params.MailSettings.ForwardingAddress = 'smtp:someone@elsewhere.example'
        Get-TestAttention $Params | Should -Be 'Mail is forwarded to **smtp:someone@elsewhere.example**'
    }

    It 'renders the strip under the header when something applies' {
        $Params = New-TestModelParams
        $Params.Policies[0].state = 'enabledForReportingButNotEnforced'
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params)
        $Body | Should -Match 'Needs attention'
        $Body | Should -Match '<strong>1 Conditional Access policy</strong> is report-only'
        $Body.IndexOf('Needs attention') | Should -BeLessThan $Body.IndexOf('>Contact</span></h3>')
    }
}

Describe 'Hudu locale' {
    It 'derives a short month-name date pattern from the culture' -ForEach @(
        @{ Name = 'en-GB'; Pattern = 'd MMM yyyy' }
        @{ Name = 'en-US'; Pattern = 'MMM d yyyy' }
        @{ Name = 'de-DE'; Pattern = 'd. MMM yyyy' }
    ) {
        Get-CippExtensionUiDatePattern ([cultureinfo]::GetCultureInfo($Name)) | Should -BeExactly $Pattern
    }

    It 'orders rendered dates by the culture' {
        $Params = New-TestModelParams
        $GbParams = New-TestModelParams
        $Params.Culture = [cultureinfo]::GetCultureInfo('en-US')
        $Us = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf -Culture $Params.Culture
        $Gb = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @GbParams) -SyncedAt $script:AsOf
        $Us | Should -Match 'Synced Oct 20 2026 12:00 UTC'
        $Us | Should -Match 'Last activity</td><td[^>]*>Oct 18 2026<'
        $Gb | Should -Match 'Synced 20 Oct 2026 12:00 UTC'
        $Gb | Should -Match 'Last activity</td><td[^>]*>18 Oct 2026<'
    }
}

Describe 'Hudu time zone' {
    It 'shows the Synced time in <Zone> with its offset and keeps the tooltip in UTC' -ForEach @(
        @{ Zone = 'UTC'; Expected = 'Synced 20 Oct 2026 12:00 UTC' }
        @{ Zone = 'Europe/London'; Expected = 'Synced 20 Oct 2026 13:00 (UTC+01:00)' }
        @{ Zone = 'America/New_York'; Expected = 'Synced 20 Oct 2026 08:00 (UTC-04:00)' }
    ) {
        $Html = New-CippExtensionUiSynced -SyncedAt $script:AsOf -TimeZone ([TimeZoneInfo]::FindSystemTimeZoneById($Zone))
        $Html | Should -Match ([regex]::Escape(">$Expected<"))
        $Html | Should -Match 'title="Last Updated: 2026-10-20 12:00:00 UTC"'
    }

    It 'uses the offset in effect on the day' {
        $Winter = [datetime]::new(2026, 1, 15, 12, 0, 0, [System.DateTimeKind]::Utc)
        New-CippExtensionUiSynced -SyncedAt $Winter -TimeZone ([TimeZoneInfo]::FindSystemTimeZoneById('Europe/London')) | Should -Match '>Synced 15 Jan 2026 12:00 UTC<'
    }

    It 'puts a late-evening UTC date on the local day' {
        $Params = New-TestModelParams
        $Params.Devices[0].lastSyncDateTime = '2026-10-19T23:30:00Z'
        (Get-CippExtensionUserViewModel @Params).Devices.Items[0].LastSync | Should -Be '19 Oct 2026'
        $Params.TimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/London')
        (Get-CippExtensionUserViewModel @Params).Devices.Items[0].LastSync | Should -Be '20 Oct 2026'
    }

    It 'converts timestamps but leaves date-only values on their own day' {
        $Params = New-TestModelParams
        $Params.TimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York')
        $Params.OneDrive.lastActivityDate = '2026-10-17'
        $Params.Devices[0].enrolledDateTime = '2026-10-17T02:00:00Z'
        $Model = Get-CippExtensionUserViewModel @Params
        $Model.OneDrive.LastActivity | Should -Be '17 Oct 2026'
        $Model.Devices.Items[0].Enrolled | Should -Be '16 Oct 2026'
    }

    It 'renders the body in the zone it is given' {
        $Params = New-TestModelParams
        $Params.TimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York')
        $Body = Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -SyncedAt $script:AsOf -TimeZone $Params.TimeZone
        $Body | Should -Match '>Synced 20 Oct 2026 08:00 \(UTC-04:00\)<'
        Get-CippExtensionUserBody -Model (Get-CippExtensionUserViewModel @Params) -TimeZone $Params.TimeZone | Should -Not -Match 'Synced'
    }
}
