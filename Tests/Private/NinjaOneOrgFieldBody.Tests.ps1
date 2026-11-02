BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Documentation/*.ps1", "$PSScriptRoot/../../Modules/CippExtensions/Private/NinjaOne/*.ps1" | ForEach-Object { . $_.FullName }

    $script:AsOf = [datetime]::new(2026, 10, 20, 12, 0, 0, [System.DateTimeKind]::Utc)
    $script:Evil = '<script>alert(1)</script>"x'

    function New-TestUser([int]$N) {
        @{
            Name = "User $N"; Upn = "user$N@fabrikam.example"; Licenses = @('SPB')
            Mailbox = @{ Pct = '90'; Text = '90% of 50 GB' }; OneDrive = $null
            Devices = @(@{ Name = "PC-$N"; Url = 'https://app.ninjarmm.com/#/deviceDashboard/1/overview'; Compliant = $true; Os = 'Windows'; LastLogin = '2026-10-19' })
            CippUrl = 'https://cipp.example/identity/administration/users/user?userId=1'; EntraUrl = 'https://entra.microsoft.com/fabrikam.example/#view/x'
        }
    }

    function New-TestModels {
        @{
            TenantLinks   = @{
                Portals     = @(@{ Label = 'M365 Admin Portal'; Url = 'https://admin.cloud.microsoft?delegatedOrg=fabrikam.example'; Tip = 'Open M365 Admin Portal' })
                CippActions = @(@{ Label = 'List Users'; Url = 'https://cipp.example/identity/administration/users'; Tip = 'List Users in CIPP' })
            }
            TenantSummary = @{
                Tiles       = @(
                    [PSCustomObject]@{ Label = 'Unused Licenses'; Value = 4; Tone = 'err'; Url = 'https://cipp.example/licenses' }
                    [PSCustomObject]@{ Label = 'Unified Audit Log'; Icon = 'circle-check'; Tone = 'ok'; Url = 'https://security.microsoft.com/audit' }
                    [PSCustomObject]@{ Label = 'OAuth App Consent'; Icon = 'circle-question'; Tone = 'neutral'; Url = 'https://entra.microsoft.com/x'; Note = 'No cached data - run the tenant data cache' }
                )
                Header      = @{ TenantName = 'Fabrikam'; DefaultDomain = 'fabrikam.example'; TenantId = '11111111-2222-4333-8444-555555555555' }
                Details     = @{ Created = '2023-01-18T09:30:00Z'; Domains = @('fabrikam.example', 'fabrikam.onmicrosoft.com'); Admins = @('Ada Admin') }
                Licenses    = @{ Url = 'https://cipp.example/licenses'; Items = @(@{ Name = 'SPB'; Active = 10; Consumed = 6; Unused = 4 }) }
                Devices     = @{
                    Url    = 'https://cipp.example/devices'
                    Charts = @(
                        @{ Title = 'Device Compliance'; Items = @(@{ Label = 'Compliant'; Amount = 3; Tone = 'ok' }, @{ Label = 'Non Compliant'; Amount = 1; Tone = 'err' }) }
                        @{ Title = 'Device Operating Systems'; Items = @(@{ Label = 'Windows'; Amount = 3; Colour = '#0078D7' }, @{ Label = 'iOS'; Amount = 1; Colour = 'red;background:red' }, @{ Label = 'Android'; Amount = 0; Colour = '#3DDC84' }) }
                    )
                }
                Standards   = @{ Url = 'https://cipp.example/standards'; Items = @(@{ Standard = 'Audit log'; Template = 'Baseline'; Actions = @('Remediate', 'Report') }) }
                SecureScore = @{ Url = 'https://security.microsoft.com/securescore'; Current = 50; Max = 80; Actions = @(@{ Action = 'Turn on MFA'; Impact = 1.5; Category = 'Identity'; Url = 'https://security.microsoft.com/securescore?actionId=mfa' }) }
                Users       = @{ Url = 'https://cipp.example/users'; Charts = @(@{ Title = 'User Status'; Items = @(@{ Label = 'Sign-In Enabled'; Amount = 2; Tone = 'ok' }, @{ Label = 'Sign-In Blocked'; Amount = 2; Tone = 'err' }) }) }
            }
            UsersSummary  = @{ Users = @(1..3 | ForEach-Object { New-TestUser $_ }); Total = 3; Url = 'https://cipp.example/users' }
        }
    }
    function Get-TestField([string]$Field, $Models = (New-TestModels)) { Get-NinjaOneOrgFieldBody -Field $Field -Model $Models[$Field] -SyncedAt $script:AsOf }
}

Describe 'Get-NinjaOneOrgFieldBody' {
    It 'renders the portal and CIPP action cards side by side' {
        $Body = Get-TestField TenantLinks
        foreach ($Text in '>Portals</span></h3>', '>CIPP Actions</span></h3>', '>M365 Admin Portal<', '>List Users<') { $Body | Should -Match ([regex]::Escape($Text)) }
        [regex]::Matches($Body, 'class="col-lg-6 col-md-12 col-sm-12 d-flex"').Count | Should -Be 2
        $Body | Should -Match 'border:1px solid rgba\(247,127,0,.7\)[^"]*">List Users</a>'
    }

    It 'renders every tenant summary section' {
        $Body = Get-TestField TenantSummary
        foreach ($Heading in 'Tenant Details', 'Licenses', 'Device Details', 'CIPP Applied Standards', 'Secure Score', 'User Details') {
            $Body | Should -Match ">$Heading( <span|</span>)"
        }
        foreach ($Text in '>Unused Licenses</a>', '>Unified Audit Log</a>', 'fa-circle-check', 'fa-circle-question', 'No cached data - run the tenant data cache', 'Fabrikam',
            '11111111-2222-4333-8444-555555555555', 'Synced 20 Oct 2026 12:00 UTC', 'fabrikam.onmicrosoft.com', 'Ada Admin', 'Device Operating Systems', 'Turn on MFA', '62.5%', 'Baseline', '>Remediate<') {
            $Body | Should -Match ([regex]::Escape($Text))
        }
        # Tables take half the width, the details card a third and the licence table the rest
        [regex]::Matches($Body, 'class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex"').Count | Should -Be 1
        [regex]::Matches($Body, 'class="col-xl-8 col-lg-6 col-md-12 col-sm-12 d-flex"').Count | Should -Be 1
        [regex]::Matches($Body, 'class="col-xl-6 col-lg-6 col-md-12 col-sm-12 d-flex"').Count | Should -Be 4
        [regex]::Matches($Body, 'class="col-xl-2 col-lg-3 col-md-4 col-sm-6 d-flex"').Count | Should -Be 3
        $Body | Should -Match 'color:#F04438">4</div>'
        $Body | Should -Match 'href="https://security\.microsoft\.com/securescore"[^>]*>Open'
    }

    It 'renders Score Impact as a signed percentage' {
        Get-TestField TenantSummary | Should -Match '>\+1\.5%</span>'
    }

    It 'formats the creation date day first for en-GB' {
        Get-TestField TenantSummary | Should -Match '>18 Jan 2023</td>'
    }

    It 'sizes chart segments from the counts and skips empty ones' {
        $Body = Get-TestField TenantSummary
        $Body | Should -Match ([regex]::Escape('width:75%;height:8px;border:4px solid #10B981'))
        $Body | Should -Match ([regex]::Escape('width:25%;height:8px;border:4px solid #F04438'))
        $Body | Should -Match ([regex]::Escape('width:50%;height:8px;border:4px solid #10B981'))
        $Os = [regex]::Match($Body, 'Device Operating Systems.*?User Status').Value
        $Widths = [regex]::Matches($Os, 'display:inline-block;vertical-align:top;width:([\d.]+)%').Groups | Where-Object Name -EQ '1' | ForEach-Object { [double]$_.Value }
        $Widths | Should -Be @(75, 25)
        $Os | Should -Match 'Android <span style="font-weight:600">0</span>'
        $Os | Should -Not -Match 'red;background'
    }

    It 'renders the users table with kit styles' {
        $Body = Get-TestField UsersSummary
        foreach ($Head in 'Name', 'User Principal Name', 'Licenses', 'Mailbox Usage', 'OneDrive Usage', 'Devices (Last Login)', 'Actions') { $Body | Should -Match ">$([regex]::Escape($Head))</th>" }
        foreach ($Text in 'user1@fabrikam.example', '>SPB<', '90% of 50 GB', 'Not enabled', '>PC-1</a>', '(19 Oct 2026)', 'fab fa-windows', '>CIPP</a>', '>Entra') { $Body | Should -Match ([regex]::Escape($Text)) }
        $Body | Should -Match ([regex]::Escape('border:4px solid #F79009'))
        $Body | Should -Not -Match 'users found in Tenant'
    }

    It 'caps the users table at 100 rows and links to CIPP for the rest' {
        $Models = New-TestModels
        $Models.UsersSummary.Users = @(1..120 | ForEach-Object { New-TestUser $_ })
        $Models.UsersSummary.Total = 250
        $Body = Get-TestField UsersSummary $Models
        ([regex]::Matches($Body, '<tr>').Count - 1) | Should -Be 100
        $Body | Should -Match '250 users found in Tenant'
        $Body | Should -Match 'Only the first 100 users are displayed here\. To see all users please <a href="https://cipp\.example/users"[^>]*>view users in CIPP</a>'
        $Body | Should -Match 'border-left:4px solid #F79009'
    }

    It 'uses nothing the NinjaOne sanitiser strips in <Field>' -ForEach @(@{ Field = 'TenantLinks' }, @{ Field = 'TenantSummary' }, @{ Field = 'UsersSummary' }) {
        $Body = Get-TestField $Field
        $Body | Should -Not -Match 'background|opacity|display:grid|border:0[;"]|(?<![\w-])border-top:'
        $Body | Should -Not -Match '<(?!a )[a-z0-9]+ [^>]*title='
        $Body | Should -Not -Match '<(code|strong|ul|li|svg)\b'
    }

    It 'pads every cell on all sides in <Field>' -ForEach @(@{ Field = 'TenantSummary' }, @{ Field = 'UsersSummary' }) {
        $Cells = [regex]::Matches((Get-TestField $Field), '<t[dh] [^>]*>').Value
        $Cells.Count | Should -BeGreaterThan 5
        $Cells | Where-Object { $_ -notmatch 'padding:7px 10px' } | Should -BeNullOrEmpty
    }

    It 'encodes hostile values' {
        $Models = New-TestModels
        $Models.TenantLinks.Portals[0].Label = $script:Evil
        $Models.TenantSummary.Header.TenantName = $script:Evil
        $Models.TenantSummary.Details.Domains = @($script:Evil)
        $Models.TenantSummary.Licenses.Items[0].Name = $script:Evil
        $Models.TenantSummary.Standards.Items[0].Standard = $script:Evil
        $Models.TenantSummary.SecureScore.Actions[0].Action = $script:Evil
        $Models.TenantSummary.Devices.Charts[0].Items[0].Label = $script:Evil
        $Models.TenantSummary.Tiles[0].Value = $script:Evil
        $Models.UsersSummary.Users[0].Name = $script:Evil
        $Models.UsersSummary.Users[0].Devices[0].Name = $script:Evil
        $Models.UsersSummary.Users[0].Devices[0].Url = 'https://n.example/d" onmouseover="alert(1)'
        foreach ($Field in 'TenantLinks', 'TenantSummary', 'UsersSummary') {
            $Body = Get-TestField $Field $Models
            $Body | Should -Not -Match '<script|"x|" onmouseover='
            $Body | Should -Match ([regex]::Escape('&lt;script&gt;alert(1)&lt;/script&gt;&quot;x'))
        }
    }
}

Describe 'ConvertTo-CippExtensionNinjaOneHtml' {
    It 'is the NinjaOne post-processing the device body applies' {
        $Device = [PSCustomObject]@{ id = 'm'; deviceName = 'L'; complianceState = 'noncompliant'; totalStorageSpaceInBytes = 512GB; freeStorageSpaceInBytes = 256GB; operatingSystem = 'Windows'; hardwareinformation = [PSCustomObject]@{} }
        $Model = Get-CippExtensionDeviceViewModel -Device $Device -Tenant ([PSCustomObject]@{ defaultDomainName = 'f.example' }) -Policies @([PSCustomObject]@{ Name = 'p'; Status = 'compliant' }) -Groups @('g') -RmmLinks @() -AsOf $script:AsOf
        Mock ConvertTo-CippExtensionNinjaOneHtml { 'converted' }
        Get-CippExtensionDeviceBody -Model $Model -Layout NinjaOne | Should -BeExactly 'converted'
        Get-CippExtensionDeviceBody -Model $Model | Should -Not -Be 'converted'
        Should -Invoke ConvertTo-CippExtensionNinjaOneHtml -Times 1 -Exactly
    }

    It 'pads cells, colours toned chips and moves accents to the left edge' {
        $Html = '<div style="border-top:3px solid #f77f00"></div><td style="x;padding:8px;padding-left:0">' +
        '<span style="background:rgba(240,68,56,.16);border:1px solid rgba(240,68,56,.6)"></span><span style="background:rgba(128,128,128,.12);border:1px solid rgba(128,128,128,.35)"></span>'
        $Out = ConvertTo-CippExtensionNinjaOneHtml -Html $Html
        $Out | Should -Match 'border-left:3px solid #f77f00'
        $Out | Should -Match '<td style="x;padding:7px 10px">'
        $Out | Should -Match 'rgba\(240,68,56,.6\);color:rgb\(240,68,56\)"'
        $Out | Should -Not -Match '128,128,128,.35\);color'
    }
}
