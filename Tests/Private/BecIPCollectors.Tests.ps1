BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version, $NoPaginateIds) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Get-CIPPTenantAllowBlockListItems { param($TenantFilter, $ListType) }
    function Get-CIPPIPAllowBlockList { param($TenantFilter) }
    function Get-NormalizedError { param($message) $message }
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $UserIds, $IPAddresses, $Anchor, $MaxPages) }
    foreach ($File in @('ConvertTo-CIPPODataFilterValue.ps1', 'Authentication/ConvertTo-CIPPIPRange.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecSignInBaseline.ps1', 'BEC/Get-CIPPBecIPPeers.ps1', 'BEC/Get-CIPPBecCorrelatedUserPeers.ps1', 'BEC/Get-CIPPBecIPGuidance.ps1', 'BEC/Get-CIPPBecBlastRadius.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    function New-SignIn {
        param($IP, $When, $Ok = $true, $Asn = 1221, $City = 'Sydney', $App = 'Outlook')
        [pscustomobject]@{ createdDateTime = $When; ipAddress = $IP; autonomousSystemNumber = $Asn; location = [pscustomobject]@{ countryOrRegion = 'AU'; city = $City }; conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = $(if ($Ok) { 0 } else { 50126 }) }; appDisplayName = $App; resourceDisplayName = 'Office 365 Exchange Online' }
    }
}

Describe 'Get-CIPPBecSignInBaseline' {
    It 'profiles successful sign-ins by address, network and location across interactive and service sign-ins' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'Interactive'; status = 200; body = [pscustomobject]@{ value = @(
                            (New-SignIn -IP '203.0.113.10' -When '2026-09-01T01:00:00Z')
                            (New-SignIn -IP '203.0.113.10' -When '2026-09-02T01:00:00Z')
                            (New-SignIn -IP '198.51.100.7' -When '2026-09-03T01:00:00Z' -Ok $false -Asn 14061 -City 'Lagos')
                        ) } }
                [pscustomobject]@{ id = 'NonInteractive'; status = 200; body = [pscustomobject]@{ value = @(
                            (New-SignIn -IP '203.0.113.10' -When '2026-09-02T02:00:00Z' -App 'SharePoint Online')
                            (New-SignIn -IP '192.0.2.44' -When '2026-09-04T01:00:00Z' -City 'Melbourne')
                        ) } }
            )
        }
        $Result = Get-CIPPBecSignInBaseline -TenantFilter 'contoso.com' -UserId '11111111-1111-1111-1111-111111111111' -StartDate '2026-08-15' -EndDate '2026-09-16'
        $Result.Complete | Should -BeTrue
        $Result.Data.Successful | Should -Be 4 -Because 'the failed spray attempt must not teach the baseline an attacker address'
        $Office = $Result.Data.IPs | Where-Object IP -EQ '203.0.113.10'
        $Office.SignIns | Should -Be 3
        $Office.Interactive | Should -Be 2
        $Office.NonInteractive | Should -Be 1
        $Office.Days | Should -Be 2
        $Office.Share | Should -Be 0.75
        $Office.Apps | Should -Contain 'SharePoint Online'
        ($Result.Data.IPs | Where-Object IP -EQ '198.51.100.7') | Should -BeNullOrEmpty
        ($Result.Data.Locations | Where-Object City -EQ 'Sydney').Share | Should -Be 0.75
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests).Count -eq 2 -and $Requests[1].url -match "nonInteractiveUser" -and $Requests[0].url -match 'createdDateTime lt ' }
    }

    It 'reports a failed half and a Graph paging stop without losing the other half' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'Interactive'; status = 200; PagingIncomplete = $true; body = [pscustomobject]@{ value = @(New-SignIn -IP '203.0.113.10' -When '2026-09-01T01:00:00Z') } }
                [pscustomobject]@{ id = 'NonInteractive'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Tenant does not have a premium licence' } } }
            )
        }
        $Result = Get-CIPPBecSignInBaseline -TenantFilter 'contoso.com' -UserId '11111111-1111-1111-1111-111111111111' -StartDate '2026-08-15' -EndDate '2026-09-16'
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Match 'NonInteractive sign-ins: Tenant does not have a premium licence'
        $Result.Data.Successful | Should -Be 1
    }
}

Describe 'Get-CIPPBecIPPeers' {
    It 'splits other accounts into before and only-in-window, excluding the investigated user, and samples service sign-ins' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'i0'; status = 200; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{ userId = 'me'; userPrincipalName = 'victim@contoso.com'; createdDateTime = '2026-09-01T00:00:00Z' }
                            [pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; createdDateTime = '2026-09-01T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                            [pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; createdDateTime = '2026-09-03T00:00:00Z'; status = [pscustomobject]@{ errorCode = 50126 } }
                        ) } }
                [pscustomobject]@{ id = 'n0'; status = 200; body = [pscustomobject]@{ '@odata.nextLink' = 'more'; value = @([pscustomobject]@{ userId = 'b'; userPrincipalName = 'b@contoso.com'; createdDateTime = '2026-09-02T00:00:00Z' }) } }
                [pscustomobject]@{ id = 'i1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ userId = 'c'; userPrincipalName = 'c@contoso.com'; createdDateTime = '2026-09-20T00:00:00Z' }) } }
                [pscustomobject]@{ id = 'n1'; status = 200; body = [pscustomobject]@{ value = @() } }
            )
        }
        $Peers = Get-CIPPBecIPPeers -TenantFilter 'contoso.com' -UserId 'me' -IPs @('203.0.113.10', '198.51.100.7') -StartDate '2026-08-15' -WindowStart '2026-09-16'
        $Peers['203.0.113.10'].OtherUsersBefore | Should -Be 2
        $Peers['203.0.113.10'].Users | Should -Not -Contain 'victim@contoso.com'
        $Peers['203.0.113.10'].Sampled | Should -BeTrue
        $A = $Peers['203.0.113.10'].Accounts | Where-Object UserPrincipalName -EQ 'a@contoso.com'
        $A.UserId | Should -Be 'a'
        $A.Successful | Should -Be 1
        $A.Failed | Should -Be 1
        $A.FirstSeen | Should -Be '2026-09-01T00:00:00Z'
        $A.LastSeen | Should -Be '2026-09-03T00:00:00Z'
        $Peers['203.0.113.10'].Accounts.UserPrincipalName | Should -Not -Contain 'victim@contoso.com'
        $Peers['198.51.100.7'].OtherUsersInWindowOnly | Should -Be 1
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($NoPaginateIds) -contains 'n0' -and @($NoPaginateIds) -contains 'n1' -and $Requests[0].url -match "ipAddress eq '203.0.113.10'" }
    }

    It 'reads the non-interactive sign-ins before the window separately, so a busy address still shows its colleagues' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'i0'; status = 200; body = [pscustomobject]@{ value = @() } }
                # the in-window page is full of token refreshes...
                [pscustomobject]@{ id = 'n0'; status = 200; body = [pscustomobject]@{ '@odata.nextLink' = 'more'; value = @([pscustomobject]@{ userId = 'x'; userPrincipalName = 'x@contoso.com'; createdDateTime = '2026-09-20T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }) } }
                # ...and the colleagues show up in the before-window page
                [pscustomobject]@{ id = 'b0'; status = 200; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; createdDateTime = '2026-09-01T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                            [pscustomobject]@{ userId = 'b'; userPrincipalName = 'b@contoso.com'; createdDateTime = '2026-09-02T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                        ) } }
            )
        }
        $Peers = Get-CIPPBecIPPeers -TenantFilter 'contoso.com' -UserId 'me' -IPs @('203.0.113.10') -StartDate '2026-08-15' -WindowStart '2026-09-16'
        $Peers['203.0.113.10'].OtherUsersBefore | Should -Be 2
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $N = $Requests | Where-Object { $_.id -eq 'n0' }; $B = $Requests | Where-Object { $_.id -eq 'b0' }
            $N.url -notmatch 'createdDateTime lt ' -and $B.url -match 'createdDateTime lt ' -and @($NoPaginateIds) -contains 'b0'
        }
    }

    It 'looks an IPv6 address up by its /64 once for all its addresses, and keeps only sign-ins inside it' {
        Mock New-GraphBulkRequest {
            @([pscustomobject]@{ id = 'i0'; status = 200; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; ipAddress = '2001:db8:1:2::77'; createdDateTime = '2026-09-01T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                            [pscustomobject]@{ userId = 'b'; userPrincipalName = 'b@contoso.com'; ipAddress = '2001:db8:1:2:9::1'; createdDateTime = '2026-09-02T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                            [pscustomobject]@{ userId = 'z'; userPrincipalName = 'z@contoso.com'; ipAddress = '2001:db8:1:20::1'; createdDateTime = '2026-09-02T00:00:00Z'; status = [pscustomobject]@{ errorCode = 0 } }
                        ) } })
        }
        $Peers = Get-CIPPBecIPPeers -TenantFilter 'contoso.com' -UserId 'me' -IPs @('2001:db8:1:2::5', '2001:db8:1:2:abcd::1') -StartDate '2026-08-15' -WindowStart '2026-09-16'
        foreach ($IP in @('2001:db8:1:2::5', '2001:db8:1:2:abcd::1')) {
            $Peers[$IP].OtherUsersBefore | Should -Be 2
            $Peers[$IP].Network | Should -Be '2001:db8:1:2::/64'
        }
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests).Count -eq 3 -and $Requests[0].url -match "startswith\(ipAddress,'2001:db8:1:2:'\)" }
    }

    It 'returns nothing without calling Graph when there are no addresses' {
        Mock New-GraphBulkRequest { throw 'should not be called' }
        (Get-CIPPBecIPPeers -TenantFilter 'contoso.com' -UserId 'me' -IPs @() -StartDate '2026-08-15' -WindowStart '2026-09-16').Count | Should -Be 0
    }
}

Describe 'Get-CIPPBecCorrelatedUserPeers' {
    It 'matches a colleague on the /64 of an IPv6 case address, before or during the window' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'i0'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; ipAddress = '2001:db8:1:2::77'; createdDateTime = '2026-09-01T00:00:00Z' }) } }
                [pscustomobject]@{ id = 'b0'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ userId = 'a'; userPrincipalName = 'a@contoso.com'; ipAddress = '203.0.113.10'; createdDateTime = '2026-09-02T00:00:00Z' }) } }
                [pscustomobject]@{ id = 'n1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ userId = 'b'; userPrincipalName = 'b@contoso.com'; ipAddress = '2001:db8:9::1'; createdDateTime = '2026-09-20T00:00:00Z' }) } }
            )
        }
        $Peers = Get-CIPPBecCorrelatedUserPeers -TenantFilter 'contoso.com' -UserIds @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222') -IPs @('2001:db8:1:2::5', '203.0.113.10') -StartDate '2026-08-15' -WindowStart '2026-09-16'
        $Peers['2001:db8:1:2::5'].OtherUsersBefore | Should -Be 1
        $Peers['2001:db8:1:2::5'].Network | Should -Be '2001:db8:1:2::/64'
        $Peers['203.0.113.10'].OtherUsersBefore | Should -Be 1 -Because 'the before-window page is read on its own'
        $Peers.Keys | Should -Not -Contain '2001:db8:9::1'
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($NoPaginateIds) -contains 'b0' -and @($NoPaginateIds) -contains 'n1' }
    }
}

Describe 'Get-CIPPBecBlastRadius' {
    BeforeAll {
        $script:Verdicts = @(
            [pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'LikelyAttacker' }
            [pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'Suspicious' }
            [pscustomobject]@{ IP = '192.0.2.50'; Verdict = 'Compromised' }
        )
    }

    It 'lists the other accounts the attacker addresses reached from sign-ins and the tenant-wide audit log' {
        $Peers = @{
            '198.51.100.7' = [pscustomobject]@{ IP = '198.51.100.7'; OtherUsers = 2; Accounts = @(
                    [pscustomobject]@{ UserPrincipalName = 'b@contoso.com'; UserId = 'b'; Successful = 2; Failed = 0; FirstSeen = '2026-09-17T01:00:00Z'; LastSeen = '2026-09-18T01:00:00Z' }
                    [pscustomobject]@{ UserPrincipalName = 'c@contoso.com'; UserId = 'c'; Successful = 0; Failed = 5; FirstSeen = '2026-09-17T02:00:00Z'; LastSeen = '2026-09-17T03:00:00Z' }
                ) }
        }
        # 192.0.2.50 was never looked up (settled outright): the blast radius looks it up itself
        Mock Get-CIPPBecIPPeers { @{ '192.0.2.50' = [pscustomobject]@{ IP = '192.0.2.50'; OtherUsers = 0; Accounts = @() } } }
        Mock Search-CIPPBecAuditLog {
            [pscustomobject]@{ Complete = $true; Cap = $null; Records = @(
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ UserId = 'd@contoso.com'; Operation = 'FileDownloaded'; ClientIP = '192.0.2.50:4431'; CreationTime = '2026-09-19T00:00:00' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ UserId = 'd@contoso.com'; Operation = 'FileDownloaded'; ClientIP = '192.0.2.50'; CreationTime = '2026-09-19T01:00:00' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ UserId = 'b@contoso.com'; Operation = 'MailItemsAccessed'; ClientIP = '198.51.100.7'; CreationTime = '2026-09-18T02:00:00' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ UserId = 'Victim@contoso.com'; Operation = 'MailItemsAccessed'; ClientIP = '198.51.100.7'; CreationTime = '2026-09-18T02:00:00' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ UserId = 'app@sharepoint'; Operation = 'FileAccessed'; ClientIP = '198.51.100.7'; CreationTime = '2026-09-18T02:00:00' } }
                ) }
        }
        Mock New-GraphBulkRequest { @([pscustomobject]@{ id = 'u0'; status = 200; body = [pscustomobject]@{ id = 'd' } }) }

        $Result = Get-CIPPBecBlastRadius -TenantFilter 'contoso.com' -UserId 'me' -UserPrincipalName 'victim@contoso.com' -Verdicts $script:Verdicts -Peers $Peers -StartDate '2026-09-16' -EndDate '2026-09-23'
        $Result.Complete | Should -BeTrue
        @($Result.Data).Count | Should -Be 3 -Because 'the investigated user and service principals are not other accounts'
        Should -Invoke Get-CIPPBecIPPeers -Times 1 -ParameterFilter { @($IPs) -join ',' -eq '192.0.2.50' }
        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { -not $UserIds -and (@($IPAddresses) -join ',') -eq '198.51.100.7,192.0.2.50' } -Because 'Suspicious addresses stay out of the blast radius'

        $B = $Result.Data | Where-Object UserPrincipalName -EQ 'b@contoso.com'
        $B.Reached | Should -BeTrue
        $B.SuccessfulSignIns | Should -Be 2
        $B.Actions | Should -Be 1
        $B.LastSeen | Should -Be '2026-09-18T02:00:00Z'
        $D = $Result.Data | Where-Object UserPrincipalName -EQ 'd@contoso.com'
        $D.UserId | Should -Be 'd' -Because 'an account seen only in the audit log is resolved so it can be investigated'
        $D.Operations | Should -Be 'FileDownloaded x2'
        $D.AttackerIPs | Should -Be '192.0.2.50'
        $C = $Result.Data | Where-Object UserPrincipalName -EQ 'c@contoso.com'
        $C.Reached | Should -BeFalse -Because 'failed sign-ins alone are an attempt'
        $Result.Data[-1].UserPrincipalName | Should -Be 'c@contoso.com'
    }

    It 'does nothing without an attacker address' {
        Mock Search-CIPPBecAuditLog { throw 'should not be called' }
        $Result = Get-CIPPBecBlastRadius -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Verdicts @([pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'Unknown' }) -StartDate '2026-09-16' -EndDate '2026-09-23'
        @($Result.Data).Count | Should -Be 0
        $Result.Complete | Should -BeTrue
    }

    It 'reports a capped audit search as partial and a failed one as an error, keeping the sign-in rows' {
        $Peers = @{ '198.51.100.7' = [pscustomobject]@{ IP = '198.51.100.7'; OtherUsers = 1; Accounts = @([pscustomobject]@{ UserPrincipalName = 'b@contoso.com'; UserId = 'b'; Successful = 1; Failed = 0 }) } }
        Mock Get-CIPPBecIPPeers { @{} }
        Mock Search-CIPPBecAuditLog { [pscustomobject]@{ Complete = $false; Cap = '10 pages'; Records = @() } }
        $Partial = Get-CIPPBecBlastRadius -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Verdicts @($script:Verdicts[0]) -Peers $Peers -StartDate '2026-09-16' -EndDate '2026-09-23'
        $Partial.Complete | Should -BeFalse
        $Partial.Cap | Should -Be '10 pages'
        Mock Search-CIPPBecAuditLog { throw 'UAL down' }
        $Failed = Get-CIPPBecBlastRadius -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Verdicts @($script:Verdicts[0]) -Peers $Peers -StartDate '2026-09-16' -EndDate '2026-09-23'
        $Failed.Error | Should -Match 'UAL down'
        @($Failed.Data).UserPrincipalName | Should -Be 'b@contoso.com'
    }
}

Describe 'Get-CIPPBecIPGuidance' {
    It 'gathers the CIPP list as deciding entries and the named locations and Exchange lists as hints' {
        Mock Get-CIPPIPAllowBlockList { @([pscustomobject]@{ Range = '198.51.100.0/24'; State = 'Blocked'; Scope = 'AllTenants'; Prefix = 24; Note = 'kit' }) }
        Mock New-GraphGetRequest { @(
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'HQ'; isTrusted = $true; ipRanges = @([pscustomobject]@{ cidrAddress = '203.0.113.0/24' }) }
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'Blocked countries IPs'; isTrusted = $false; ipRanges = @([pscustomobject]@{ cidrAddress = '192.0.2.0/24' }) }
            ) }
        Mock Get-CIPPTenantAllowBlockListItems { @([pscustomobject]@{ Value = '2001:db8::1'; Action = 'Block'; Notes = $null }) }
        Mock New-ExoRequest { @([pscustomobject]@{ Name = 'Default'; IPAllowList = @('192.0.2.10', '192.0.2.20-192.0.2.30'); IPBlockList = @() }) }
        $Result = Get-CIPPBecIPGuidance -TenantFilter 'contoso.com'
        $Result.Complete | Should -BeTrue
        ($Result.Data | Where-Object Range -EQ '198.51.100.0/24').Strength | Should -Be 'List'
        ($Result.Data | Where-Object Range -EQ '203.0.113.0/24').Source | Should -Be "Trusted named location 'HQ'"
        ($Result.Data | Where-Object Range -EQ '192.0.2.0/24') | Should -BeNullOrEmpty -Because 'only trusted named locations say anything about the user'
        ($Result.Data | Where-Object Range -EQ '2001:db8::1').Verdict | Should -Be 'Blocked'
        @($Result.Data | Where-Object Source -Like 'Connection filter*').Range | Should -Be @('192.0.2.10') -Because 'hyphenated ranges are skipped'
    }

    It 'keeps the other sources when one fails and reports it' {
        Mock Get-CIPPIPAllowBlockList { @([pscustomobject]@{ Range = '198.51.100.7'; State = 'Trusted'; Scope = 'Tenant'; Prefix = 32 }) }
        Mock New-GraphGetRequest { throw 'Forbidden' }
        Mock Get-CIPPTenantAllowBlockListItems { @() }
        Mock New-ExoRequest { @() }
        $Result = Get-CIPPBecIPGuidance -TenantFilter 'contoso.com'
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Match 'named locations: Forbidden'
        @($Result.Data).Count | Should -Be 1
    }
}
