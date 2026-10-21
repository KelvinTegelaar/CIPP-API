BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }

    $script:AsOf = [datetime]::new(2026, 10, 20, 22, 57, 0, [System.DateTimeKind]::Utc)
    $script:GaTemplate = '62e90394-69f5-4237-9190-012177145e10'

    function New-Member([string]$Name, [string]$Id, [string]$Type) {
        $Member = [PSCustomObject]@{ displayName = $Name; id = $Id }
        if ($Type) { $Member | Add-Member -NotePropertyName '@odata.type' -NotePropertyValue "#microsoft.graph.$Type" }
        $Member
    }
    function New-License([string]$Name, [int]$Active, [int]$Used) { [PSCustomObject]@{ SkuPartNumber = $Name; PrepaidUnits = @{ Enabled = $Active }; ConsumedUnits = $Used } }

    function New-DashParams {
        @{
            Tenant   = [PSCustomObject]@{ displayName = 'Fabrikam Labs'; defaultDomainName = 'fabrikam.example'; customerId = '11111111-2222-4333-8444-555555555555' }
            Links    = @(
                @{ Title = 'M365 Admin Portal'; URL = 'https://admin.cloud.microsoft?delegatedOrg=fabrikam.onmicrosoft.com'; Icon = 'fas fa-cogs' }
                @{ Title = 'Defender Portal'; URL = 'https://security.microsoft.com/?tid=11111111-2222-4333-8444-555555555555'; Icon = 'fas fa-shield' }
            )
            Domains  = @([PSCustomObject]@{ id = 'fabrikam.example'; isVerified = $true }, [PSCustomObject]@{ id = 'pending.example'; isVerified = $false })
            Licenses = @((New-License 'Business Premium' 10 6), (New-License 'Copilot' 5 0), (New-License 'Teams Rooms Resource Account' 2 1))
            Roles    = @(
                [PSCustomObject]@{ DisplayName = 'Global Administrator'; RoleTemplateId = $script:GaTemplate; Members = @((New-Member 'Ada Admin'), (New-Member 'Grace Admin')); EligibleMembers = 'Ola Oncall (until 2030-01-15)' }
                [PSCustomObject]@{ DisplayName = 'Helpdesk Administrator'; RoleTemplateId = 'hd'; Members = @(1..8 | ForEach-Object { New-Member "Helper $_" }); EligibleMembers = '' }
                [PSCustomObject]@{ DisplayName = 'Unused Role'; RoleTemplateId = 'unused'; Members = @(); EligibleMembers = '' }
            )
            Users    = @(
                [PSCustomObject]@{ id = 'u1'; displayName = 'Ada Admin'; userPrincipalName = 'ada@fabrikam.example'; Licenses = @('Business Premium'); HuduUrl = 'https://hudu.example/a/1'; Devices = @([PSCustomObject]@{ name = 'LAPTOP-1'; os = 'Windows' }) }
                [PSCustomObject]@{ id = 'u2'; displayName = 'Mixed User'; userPrincipalName = 'mixed@fabrikam.example'; Licenses = @('Business Premium', 'Teams Rooms Resource Account'); HuduUrl = $null; Devices = @() }
                [PSCustomObject]@{ id = 'u3'; displayName = 'Board Room'; userPrincipalName = 'boardroom@fabrikam.example'; Licenses = @('Teams Rooms Resource Account'); HuduUrl = $null; Devices = @() }
            )
        }
    }

    function Get-TestDash([hashtable]$Params) { Get-HuduMagicDashViewModel @Params }
}

Describe 'Get-HuduMagicDashBody' {
    It 'renders every section for a full model' {
        $Params = New-DashParams
        $Params.Licenses = @((New-License 'Business Premium' 10 10), (New-License 'Copilot' 5 0))
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf
        foreach ($Text in 'Basic info</span></h3>', '>Role holders ', '>Licenses ', 'Assigned roles', '>Licensed users ', 'Resource accounts', 'Purchased but not assigned', 'Everyone else', 'Needs attention', 'Verified domains', 'M365 Admin Portal', 'Defender Portal', 'LAPTOP-1', 'https://hudu.example/a/1') {
            $Body | Should -Match ([regex]::Escape($Text))
        }
        $Body | Should -Not -Match 'pending\.example'
    }

    It 'always renders the tenant ID' {
        $Params = New-DashParams
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params)
        $Body | Should -Match '<code[^>]*>11111111-2222-4333-8444-555555555555</code>'
    }

    It 'reads the sync time day first, in UTC' {
        $Params = New-DashParams
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf
        $Body | Should -Match '>Synced 20 Oct 2026 22:57 UTC<'
        $Body | Should -Match 'title="Last Updated: 2026-10-20 22:57:00 UTC"'
    }

    It 'uses nothing the Hudu sanitizer strips and resets table styles' {
        $Params = New-DashParams
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf
        $Body | Should -Not -Match 'gap:'
        $Body | Should -Not -Match '<svg'
        $Body | Should -Not -Match 'aria-hidden'
        $Body | Should -Match '^<div style="overflow:hidden">'
        $Body | Should -Match '<table style="width:100%;border:0;margin:0;table-layout:auto'
        $Body | Should -Match '<td style="border-width:0 0 1px;background:transparent;vertical-align:top'
    }

    It 'uses no layout CSS that Hudu or its mobile app drops' {
        $Params = New-DashParams
        $Params.Licenses = @((New-License 'Business Premium' 10 10), (New-License 'Copilot' 5 0))
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf
        $Body | Should -Match 'Needs attention'
        $Body | Should -Not -Match 'display:(inline-)?flex|justify-content|float:|gap:'
    }

    It 'uses the CIPP brand without orange text' {
        $Params = New-DashParams
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf
        $Body | Should -Match '^<div style="overflow:hidden"><div style="border:1px solid rgba\(128,128,128,.3\);border-top:3px solid #f77f00;'
        $Body | Should -Match '<i class="fas fa-user-shield" style="color:#f77f00;font-size:12px"></i></span><span style="vertical-align:middle;font-size:12px;font-weight:600;letter-spacing:1px;text-transform:uppercase;opacity:.7">Global Administrators</span></div><div style="margin-top:6px;font-size:20px;font-weight:600'
        $Body | Should -Match '<i class="fas fa-key" style="color:#f77f00;font-size:12px"></i></span><span style="vertical-align:middle">Licenses '
        $Body | Should -Match 'width:60%;background:#f77f00'
        $Body | Should -Not -Match 'border-radius:1[02]px'
        foreach ($Use in [regex]::Matches($Body, '(?<![-\w])color:#f77f00')) {
            $Body.Substring(0, $Use.Index) | Should -Match '<i class="[^"]*" style="[^"]*$'
        }
    }

    It 'underlines people linked to Hudu so they read as links' {
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash (New-DashParams))

        $Body | Should -Match '<a href="https://hudu\.example/a/1"[^>]*style="font-weight:600;color:inherit;text-decoration:underline[^"]*">Ada Admin</a>'
    }

    It 'encodes every data value' {
        $Evil = '<script>alert(1)</script>"x'
        $Params = New-DashParams
        $Params.Tenant.displayName = $Evil
        $Params.Domains = @([PSCustomObject]@{ id = $Evil; isVerified = $true })
        $Params.Licenses = @(New-License $Evil 5 1)
        $Params.Roles[0].Members = @(New-Member $Evil)
        $Params.Roles[0].EligibleMembers = $Evil
        $Params.Users[0].displayName = $Evil
        $Params.Users[0].HuduUrl = 'https://hudu.example/a/1" onmouseover="alert(1)'
        $Params.Users[0].Devices = @([PSCustomObject]@{ name = $Evil; os = $Evil })
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params) -SyncedAt $script:AsOf

        $Body | Should -Not -Match '<script'
        $Body | Should -Not -Match '"x'
        $Body | Should -Not -Match '" onmouseover='
        $Body | Should -Match ([regex]::Escape('&lt;script&gt;alert(1)&lt;/script&gt;&quot;x'))
    }

    It 'shows PIM-eligible members with their end date and keeps empty roles it is given' {
        $Params = New-DashParams
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params)
        $Body | Should -Match 'Eligible:</span> <span[^>]*>Ola Oncall \(until 2030-01-15\)</span>'
        $Body | Should -Match '>Unused Role</td><td[^>]*><span style="opacity:.55">&ndash;</span>'
    }
}

Describe 'Get-HuduMagicDashViewModel' {
    It 'splits users whose only licenses are resource accounts from people' {
        $Dash = Get-TestDash (New-DashParams)
        @($Dash.People.Name) | Should -Be @('Ada Admin', 'Mixed User')
        @($Dash.Resource) | Should -Be @('Board Room')
        $Dash.Stats.Users.Foot | Should -Match '^2 people . 1 resource account$'
    }

    It 'counts role holders once each, Global Administrators first' {
        $Dash = Get-TestDash (New-DashParams)
        $Dash.Roles.PrincipalCount | Should -Be 10
        @($Dash.Roles.Top[0..1].Name) | Should -Be @('Ada Admin', 'Grace Admin')
        $Dash.Roles.More.Count | Should -Be 2
    }

    It 'keeps role holders with the same name but different ids apart' {
        $Params = New-DashParams
        $Params.Roles = @(
            [PSCustomObject]@{ DisplayName = 'Exchange Administrator'; RoleTemplateId = 'x'; Members = @((New-Member 'CIPP-SAM' 'sp-1' 'servicePrincipal'), (New-Member 'CIPP-SAM' 'sp-2' 'servicePrincipal')); EligibleMembers = '' }
            [PSCustomObject]@{ DisplayName = 'Teams Administrator'; RoleTemplateId = 't'; Members = @((New-Member 'CIPP-SAM' 'sp-1' 'servicePrincipal')); EligibleMembers = '' }
        )
        $Dash = Get-TestDash $Params
        @($Dash.Roles.Top | ForEach-Object { "$($_.Name)=$($_.RoleCount)" }) | Should -Be @('CIPP-SAM=2', 'CIPP-SAM=1')
    }

    It 'marks service principals, by type or by app id' {
        $Params = New-DashParams
        $Sp = New-Member 'Backup App' 'sp-9'
        $Sp | Add-Member -NotePropertyName appId -NotePropertyValue 'app-9'
        $Params.Roles = @([PSCustomObject]@{ DisplayName = 'Exchange Administrator'; RoleTemplateId = 'x'; Members = @((New-Member 'Sync App' 'sp-1' 'servicePrincipal'), $Sp, (New-Member 'Ada Admin' 'u-1' 'user')); EligibleMembers = '' })
        $Dash = Get-TestDash $Params
        @($Dash.Roles.Top | Where-Object { $_.IsServicePrincipal } | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('Backup App', 'Sync App')

        $Body = Get-HuduMagicDashBody -Model $Dash
        $Icon = '<i class="fas fa-robot" title="Service principal"'
        $Body | Should -Match ([regex]::Escape("$Icon style=`"opacity:.75;margin-right:5px`"></i>Sync App</td>"))
        $Body | Should -Match ([regex]::Escape("$Icon style=`"opacity:.75;margin-right:5px`"></i>Sync App</span>"))
        $Body | Should -Match ([regex]::Escape('<i class="fas fa-user" title="User" style="opacity:.75;margin-right:5px"></i>Ada Admin</td>'))
        $Body | Should -Match ([regex]::Escape('<i class="fas fa-user" title="User" style="opacity:.75;margin-right:5px"></i>Ada Admin</span>'))
    }

    It 'titles each role holder with its identifier and the role count with its roles' {
        $Params = New-DashParams
        $User = New-Member 'Ada Admin' 'u-1' 'user'
        $User | Add-Member -NotePropertyName userPrincipalName -NotePropertyValue 'ada@fabrikam.example'
        $Sp = New-Member 'Sync App' 'sp-1' 'servicePrincipal'
        $Sp | Add-Member -NotePropertyName appId -NotePropertyValue 'app-123'
        $Group = New-Member 'Admins Group' 'g-1' 'group'
        $Params.Roles = @(
            [PSCustomObject]@{ DisplayName = 'Exchange Administrator'; RoleTemplateId = 'x'; Members = @($User, $Sp, $Group); EligibleMembers = '' }
            [PSCustomObject]@{ DisplayName = 'Teams Administrator'; RoleTemplateId = 't'; Members = @($User); EligibleMembers = '' }
        )
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params)
        $Body | Should -Match ([regex]::Escape('title="ada@fabrikam.example"><i class="fas fa-user" title="User"'))
        $Body | Should -Match ([regex]::Escape('title="app-123"><i class="fas fa-robot" title="Service principal"'))
        $Body | Should -Match ([regex]::Escape('title="g-1"><i class="fas fa-users" title="Group"'))
        $Body | Should -Match 'title="Exchange Administrator, Teams Administrator">2 roles</td>'
        $Body | Should -Match 'title="Exchange Administrator">1 role</td>'
    }

    It 'encodes a hostile identifier in the title attribute' {
        $Params = New-DashParams
        $User = New-Member 'Ada Admin' 'u-1' 'user'
        $User | Add-Member -NotePropertyName userPrincipalName -NotePropertyValue 'x" onmouseover="alert(1)<b>@fabrikam.example'
        $Params.Roles = @([PSCustomObject]@{ DisplayName = 'Exchange Administrator'; RoleTemplateId = 'x'; Members = @($User); EligibleMembers = '' })
        $Body = Get-HuduMagicDashBody -Model (Get-TestDash $Params)
        $Body | Should -Not -Match '" onmouseover='
        $Body | Should -Not -Match '<b>'
        $Body | Should -Match ([regex]::Escape('title="x&quot; onmouseover=&quot;alert(1)&lt;b&gt;@fabrikam.example"'))
    }

    It 'sets a success tile when nothing needs attention' {
        $Dash = Get-TestDash (New-DashParams)
        $Dash.Attention | Should -BeNullOrEmpty
        $Dash.Tile.Shade | Should -Be 'success'
        $Dash.Tile.Message | Should -Be '3 licensed users'
    }

    It 'sets a danger tile when something needs attention' {
        $Params = New-DashParams
        $Params.Licenses = @(New-License 'Business Premium' 10 10)
        $Dash = Get-TestDash $Params
        $Dash.Tile.Shade | Should -Be 'danger'
        $Dash.Tile.Message | Should -Be "3 licensed users $([char]0x00B7) 1 item needs attention"
    }

    It 'counts every attention item on the tile' {
        $Params = New-DashParams
        $Params.Licenses = @((New-License 'Business Premium' 10 10), (New-License 'Exchange Online' 100 95))
        $Dash = Get-TestDash $Params
        $Dash.Tile.Message | Should -Be "3 licensed users $([char]0x00B7) $(@($Dash.Attention).Count) items need attention"
        @($Dash.Attention).Count | Should -BeGreaterThan 1
    }
}

Describe 'Get-HuduMagicDashAttentionItems' {
    It 'flags a fully assigned license and not one with seats left' {
        $Params = New-DashParams
        $Params.Licenses = @(New-License 'Business Premium' 5 5)
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -Be '**1 license is** fully assigned: Business Premium'
        $Params.Licenses = @(New-License 'Business Premium' 5 4)
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -BeNullOrEmpty
    }

    It 'flags a license 90% assigned and not below' {
        $Params = New-DashParams
        $Params.Licenses = @(New-License 'Business Premium' 10 9)
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -Be '**1 license is** nearly fully assigned: Business Premium (90%)'
        $Params.Licenses = @(New-License 'Business Premium' 100 89)
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -BeNullOrEmpty
    }

    It 'counts service principals among Global Administrators and says how many' {
        $Params = New-DashParams
        $Params.Roles[0].Members = @((New-Member 'Admin 1' 'u1' 'user'), (New-Member 'Admin 2' 'u2' 'user'), (New-Member 'Admin 3' 'u3' 'user'), (New-Member 'CIPP-SAM' 'sp1' 'servicePrincipal'), (New-Member 'CIPP-SAM' 'sp2' 'servicePrincipal'))
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -Be '**5 accounts** (2 service principals) hold Global Administrator (Microsoft recommends fewer than 5)'
    }

    It 'flags five Global Administrators and not four' {
        $Params = New-DashParams
        $Params.Roles[0].Members = @(1..5 | ForEach-Object { New-Member "Admin $_" })
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -Be '**5 accounts** hold Global Administrator (Microsoft recommends fewer than 5)'
        $Params.Roles[0].Members = @(1..4 | ForEach-Object { New-Member "Admin $_" })
        Get-HuduMagicDashAttentionItems -Model (Get-TestDash $Params) | Should -BeNullOrEmpty
    }
}

Describe 'Get-HuduStaleMagicDash' {
    BeforeAll {
        $script:TenantId = '11111111-2222-4333-8444-555555555555'
        $script:Dashes = @(
            [PSCustomObject]@{ id = 1; title = 'Microsoft 365 - Fabrikam Labs'; content = "<code>$($script:TenantId)</code>" }
            [PSCustomObject]@{ id = 2; title = 'Microsoft 365 - Fabrikam'; content = "<code>$($script:TenantId)</code>" }
            [PSCustomObject]@{ id = 3; title = 'Microsoft 365 - Other Tenant'; content = '<code>99999999-2222-4333-8444-555555555555</code>' }
            [PSCustomObject]@{ id = 4; title = 'Backups - Fabrikam'; content = "<code>$($script:TenantId)</code>" }
            [PSCustomObject]@{ id = 5; title = 'Microsoft 365 - No Id'; content = '<p>legacy dash without an id</p>' }
        )
    }

    It 'selects only an old-titled dash carrying this tenant ID' {
        $Stale = @(Get-HuduStaleMagicDash -Dashes $script:Dashes -CurrentTitle 'Microsoft 365 - Fabrikam Labs' -TenantId $script:TenantId)
        @($Stale.id) | Should -Be @(2)
    }

    It 'selects nothing when there are no dashes' {
        Get-HuduStaleMagicDash -Dashes @() -CurrentTitle 'Microsoft 365 - Fabrikam Labs' -TenantId $script:TenantId | Should -BeNullOrEmpty
        Get-HuduStaleMagicDash -Dashes $null -CurrentTitle 'Microsoft 365 - Fabrikam Labs' -TenantId $script:TenantId | Should -BeNullOrEmpty
    }
}
