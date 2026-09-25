# UsageLocation is a per-user sweep: the prepare hook decides WHICH member accounts are
# wrong and GraphBulkSweep applies the same PATCH to each. Everything that can go wrong
# lives in that decision - a guest swept into a licence country, an exclusion group that
# silently resolved to nothing, a hand-set location overwritten despite 'only when blank'.
# These tests pin the offender set the hook produces from a mocked Users cache and a
# mocked transitive-membership lookup.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType, $CollectorArgs) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $Version, $scope) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineUsageLocationState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Users = @(
        [PSCustomObject]@{ id = 'u1'; userPrincipalName = 'alice@contoso.com'; userType = 'Member'; usageLocation = 'US' }
        [PSCustomObject]@{ id = 'u2'; userPrincipalName = 'bob@contoso.com'; userType = 'Member'; usageLocation = $null }
        [PSCustomObject]@{ id = 'u3'; userPrincipalName = 'carol@contoso.com'; userType = 'Member'; usageLocation = 'NL' }
        [PSCustomObject]@{ id = 'u4'; userPrincipalName = 'dave@contoso.com'; userType = 'Member'; usageLocation = 'us' }
        [PSCustomObject]@{ id = 'g1'; userPrincipalName = 'guest_outlook.com#EXT#@contoso.onmicrosoft.com'; userType = 'Guest'; usageLocation = $null }
    )
    $script:Groups = @(
        [PSCustomObject]@{ id = 'grp-overseas'; displayName = 'Overseas Staff' }
        [PSCustomObject]@{ id = 'grp-licensed'; displayName = 'Licensed Users' }
    )
    function Invoke-Hook {
        param($Variables)
        Get-CIPPBaselineUsageLocationState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant
    }
}

Describe 'Get-CIPPBaselineUsageLocationState' {
    BeforeEach {
        Mock New-CIPPDbRequest { $script:Users }
        Mock Get-CIPPBaselineCacheRows { $script:Groups }
        Mock New-GraphBulkRequest { @() }
    }

    Context 'offender set' {
        It 'flags every member whose location differs or is blank, and never a guest' {
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US' })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com', 'carol@contoso.com')
            @($Prepared.Current.targets | ForEach-Object { $_.id }) | Should -Be @('u2', 'u3')
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It 'compares the country code case-insensitively so a lowercase cached value is not permanent drift' {
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'us' })
            @($Prepared.Current.offenders) | Should -Not -Contain 'dave@contoso.com'
            @($Prepared.Current.offenders) | Should -Not -Contain 'alice@contoso.com'
        }

        It 'accepts the {label, value} wrapper a one-off hands over unflattened' {
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = [PSCustomObject]@{ label = 'United States'; value = 'US' } })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com', 'carol@contoso.com')
        }

        It 'with onlyWhenBlank, leaves a hand-set location alone and only fills the empty ones' {
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; onlyWhenBlank = $true })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com')
        }

        It 'is compliant (empty offender set) when every member already matches' {
            Mock New-CIPPDbRequest { @($script:Users | Where-Object { $_.id -in @('u1', 'u4', 'g1') }) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US' })
            @($Prepared.Current.offenders).Count | Should -Be 0
            @($Prepared.Current.targets).Count | Should -Be 0
        }
    }

    Context 'group scoping' {
        It 'drops transitive members of an exclude group from the sweep' {
            Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'exclude-grp-overseas'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u3' }) } }) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; excludeGroups = @('Overseas Staff') })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com')
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Version -eq 'v1.0' -and @($Requests).Count -eq 1 -and $Requests[0].url -like 'groups/grp-overseas/transitiveMembers/microsoft.graph.user*'
            }
        }

        It 'restricts the sweep to transitive members of an include group' {
            Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'include-grp-licensed'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u2' }, [PSCustomObject]@{ id = 'u1' }) } }) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; includeGroups = @('Licensed Users') })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com')
        }

        It 'applies exclude on top of include when both are configured' {
            Mock New-GraphBulkRequest { @(
                    [PSCustomObject]@{ id = 'include-grp-licensed'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u2' }, [PSCustomObject]@{ id = 'u3' }) } }
                    [PSCustomObject]@{ id = 'exclude-grp-overseas'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u3' }) } }
                ) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; includeGroups = @('Licensed Users'); excludeGroups = @('Overseas Staff') })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com')
        }

        It 'accepts picker wrappers for the group names, matched case-insensitively' {
            Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'exclude-grp-overseas'; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'u3' }) } }) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; excludeGroups = @([PSCustomObject]@{ label = 'overseas staff'; value = 'overseas staff' }) })
            @($Prepared.Current.offenders) | Should -Be @('bob@contoso.com')
        }

        It 'reports No Data rather than sweeping when a configured group does not exist in the tenant' {
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; excludeGroups = @('Does Not Exist') })
            $Prepared.Current | Should -BeNullOrEmpty
            Should -Invoke New-GraphBulkRequest -Times 0
        }

        It 'reports No Data when the membership lookup throws' {
            Mock New-GraphBulkRequest { throw 'Graph is down' }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; excludeGroups = @('Overseas Staff') })
            $Prepared.Current | Should -BeNullOrEmpty
        }

        It 'reports No Data when one membership request in the batch fails' {
            Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'exclude-grp-overseas'; status = 403; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'Forbidden' } } }) }
            $Prepared = Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US'; excludeGroups = @('Overseas Staff') })
            $Prepared.Current | Should -BeNullOrEmpty
        }
    }

    Context 'no data' {
        It 'reports No Data when the Users cache is empty' {
            Mock New-CIPPDbRequest { @() }
            (Invoke-Hook ([PSCustomObject]@{ usageLocation = 'US' })).Current | Should -BeNullOrEmpty
        }

        It 'reports No Data when the configured value is not a two-letter country code' {
            (Invoke-Hook ([PSCustomObject]@{ usageLocation = 'United States' })).Current | Should -BeNullOrEmpty
        }
    }
}
