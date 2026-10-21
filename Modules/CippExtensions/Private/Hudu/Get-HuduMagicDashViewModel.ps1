function Get-HuduMagicDashViewModel {
    <#
        .SYNOPSIS
        Turns tenant data into a display-ready model for Get-HuduMagicDashBody.

        .DESCRIPTION
        The model holds plain strings, numbers, bools and lists only, never HTML; the renderer encodes every value.
        Users whose licenses all match ResourceAccountPattern are listed apart from people.

        .PARAMETER Roles
        Role objects: DisplayName, RoleTemplateId, Members (with displayName) and EligibleMembers.

        .PARAMETER Users
        One object per licensed user: id, displayName, userPrincipalName, Licenses, HuduUrl and Devices (name, os).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Tenant,
        $Links,
        $Domains,
        $Licenses,
        $Roles,
        $Users,
        [cultureinfo]$Culture = [cultureinfo]::GetCultureInfo('en-GB'),
        [string]$ResourceAccountPattern = 'Resource Account',
        [int]$GlobalAdminWarnAt = 5,
        [double]$LicenseWarnPct = 90,
        [int]$PrincipalsShown = 8
    )

    $Inv = [cultureinfo]::InvariantCulture
    $Dot = [string][char]0x00B7
    $Domain = [string]$Tenant.defaultDomainName
    $n0 = { param($v) ([double]$v).ToString('N0', $Culture) }
    $Plural = { param([int]$n, $One, $Many) if ($n -eq 1) { "1 $One" } else { "$n $Many" } }

    # Licenses
    $LicRows = @(foreach ($L in @($Licenses | Where-Object { $_ -and $_.PrepaidUnits.Enabled -gt 0 })) {
            $Active = [double]$L.PrepaidUnits.Enabled
            $Used = [double]$L.ConsumedUnits
            $Pct = [math]::Round($Used / $Active * 100, 2)
            $Full = ($Used -ge $Active)
            $Near = (-not $Full -and $Pct -ge $LicenseWarnPct)
            [ordered]@{
                Name         = [string]$L.SkuPartNumber
                Consumed     = $Used
                ActiveText   = (& $n0 $Active)
                ConsumedText = (& $n0 $Used)
                UnusedText   = (& $n0 ([math]::Max(0, $Active - $Used)))
                Pct          = ([math]::Min(100, $Pct)).ToString('0.##', $Inv)
                PctText      = $Pct.ToString('0.##', $Culture) + '%'
                IsFull       = $Full
                IsNearFull   = $Near
                Tone         = $(if ($Full -or $Near) { 'warn' } else { 'ok' })
                Tip          = "$(& $n0 $Used) of $(& $n0 $Active) assigned"
            }
        })
    $InUse = @($LicRows | Where-Object { $_.Consumed -gt 0 } | Sort-Object { $_.Consumed } -Descending)
    $Unassigned = @($LicRows | Where-Object { $_.Consumed -le 0 } | Sort-Object { $_.Name })
    $FullCount = @($LicRows | Where-Object { $_.IsFull }).Count

    # Roles, including any without members. Members are keyed by principal id because display names are not unique.
    $GaTemplateId = '62e90394-69f5-4237-9190-012177145e10'
    $RoleRows = @(foreach ($R in @($Roles | Where-Object { $_ })) {
            [ordered]@{
                Name          = [string]$R.DisplayName
                Members       = @($R.Members | Where-Object { $_.displayName } | ForEach-Object {
                        $Type = [string]$_.'@odata.type'
                        $Kind = if ($Type -match 'servicePrincipal') { 'ServicePrincipal' } elseif ($Type -match 'group') { 'Group' } elseif ($Type -match 'user') { 'User' } elseif ($Type) { '' } elseif ($_.appId) { 'ServicePrincipal' } elseif ($_.userPrincipalName) { 'User' } else { '' }
                        [ordered]@{
                            Key                = $(if ($_.id) { "id:$($_.id)" } else { "name:$($_.displayName)" })
                            Name               = [string]$_.displayName
                            Kind               = $Kind
                            IsServicePrincipal = ($Kind -eq 'ServicePrincipal')
                            Identifier         = [string]$(if ($Kind -eq 'User' -and $_.userPrincipalName) { $_.userPrincipalName } elseif ($Kind -eq 'ServicePrincipal' -and $_.appId) { $_.appId } else { $_.id })
                        }
                    })
                Eligible      = [string]$R.EligibleMembers
                IsGlobalAdmin = ($R.RoleTemplateId -eq $GaTemplateId -or $R.DisplayName -eq 'Global Administrator')
            }
        })
    $GaMembers = @($RoleRows | Where-Object { $_.IsGlobalAdmin } | ForEach-Object { $_.Members } | Group-Object { $_.Key } | ForEach-Object { $_.Group[0] })
    $GaKeys = @($GaMembers | ForEach-Object { $_.Key })
    $Principals = @($RoleRows | ForEach-Object { $Role = $_; foreach ($Member in $_.Members) { [pscustomobject]@{ Member = $Member; Role = $Role.Name } } } |
            Group-Object { $_.Member.Key } | ForEach-Object {
                $RoleNames = @($_.Group.Role | Sort-Object -Unique)
                $Member = $_.Group[0].Member
                [ordered]@{
                    Name               = $Member.Name
                    Kind               = $Member.Kind
                    IsServicePrincipal = $Member.IsServicePrincipal
                    Identifier         = $Member.Identifier
                    RoleCount          = $RoleNames.Count
                    RoleLabel          = (& $Plural $RoleNames.Count 'role' 'roles')
                    IsGlobalAdmin      = ($GaKeys -contains $Member.Key)
                    RoleTip            = ($RoleNames -join ', ')
                }
            } | Sort-Object @{ Expression = { -[int]$_.IsGlobalAdmin } }, @{ Expression = { -$_.RoleCount } }, @{ Expression = { $_.Name } })

    # Users
    $AllUsers = @($Users | Where-Object { $_ })
    $IsResource = { param($u) $l = @($u.Licenses | Where-Object { $_ }); ($l.Count -gt 0) -and (@($l | Where-Object { $_ -notmatch $ResourceAccountPattern }).Count -eq 0) }
    $People = @(foreach ($U in @($AllUsers | Where-Object { -not (& $IsResource $_) } | Sort-Object displayName)) {
            $UserLicenses = @($U.Licenses | Where-Object { $_ })
            [ordered]@{
                Name         = [string]$U.displayName
                Url          = [string]$U.HuduUrl
                Address      = [string]$U.userPrincipalName
                LicenseLabel = (& $Plural $UserLicenses.Count 'license' 'licenses')
                LicenseTip   = ($UserLicenses -join ', ')
                Devices      = @($U.Devices | Where-Object { $_ } | ForEach-Object { [ordered]@{ Name = [string]$_.name; Tip = "$($_.name) ($($_.os))" } })
                EntraUrl     = "https://entra.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$($U.id)"
                AdminUrl     = "https://admin.microsoft.com/Partner/BeginClientSession.aspx?CTID=$($Tenant.customerId)&CSDEST=o365admincenter/Adminportal/Home#/users/:/UserDetails/$($U.id)"
            }
        })
    $Resource = @($AllUsers | Where-Object { & $IsResource $_ } | Sort-Object displayName | ForEach-Object { [string]$_.displayName })

    $VerifiedDomains = @($Domains | Where-Object { $_.isVerified } | ForEach-Object { [string]$_.id } | Sort-Object)

    $Model = [ordered]@{
        Header    = [ordered]@{ TenantName = [string]$Tenant.displayName; DefaultDomain = $Domain; TenantId = [string]$Tenant.customerId }
        Links     = @($Links | Where-Object { $_ } | ForEach-Object { [ordered]@{ Title = [string]$_.Title; Url = [string]$_.URL; Tip = "Open $($_.Title) in a new tab" } })
        Stats     = [ordered]@{
            Users    = [ordered]@{ Total = $AllUsers.Count; Foot = "$(& $Plural $People.Count 'person' 'people') $Dot $(& $Plural $Resource.Count 'resource account' 'resource accounts')" }
            Licenses = [ordered]@{ Total = $LicRows.Count; Foot = "$FullCount full $Dot $($Unassigned.Count) unassigned" }
            Admins   = [ordered]@{ Total = $GaMembers.Count; Foot = "$(& $Plural $Principals.Count 'account holds' 'accounts hold') at least one role" }
            Domains  = [ordered]@{ Total = $VerifiedDomains.Count; Foot = "default $Domain" }
        }
        Domains   = $VerifiedDomains
        Licenses  = [ordered]@{ Count = $LicRows.Count; Items = $LicRows; InUse = $InUse; Unassigned = $Unassigned }
        Roles     = [ordered]@{
            Items             = $RoleRows
            Top               = @($Principals | Select-Object -First $PrincipalsShown)
            More              = @($Principals | Select-Object -Skip $PrincipalsShown)
            PrincipalCount    = $Principals.Count
            GlobalAdmins      = $GaMembers
            GlobalAdminWarnAt = $GlobalAdminWarnAt
        }
        People    = $People
        Resource  = $Resource
    }
    $Model.Attention = Get-HuduMagicDashAttentionItems -Model $Model
    $Model.Tile = [ordered]@{
        Message = "$(& $Plural $AllUsers.Count 'licensed user' 'licensed users')$(if ($Model.Attention.Count) { " $Dot $(& $Plural $Model.Attention.Count 'item needs attention' 'items need attention')" })"
        Shade   = $(if ($Model.Attention.Count) { 'danger' } else { 'success' })
    }
    $Model
}
