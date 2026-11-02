# Pester tests for Invoke-CIPPStandardGroupTemplate
#
# Covers the run-to-run duplication reported when the standard could not read the tenant's
# current groups: the existing-groups read returning nothing (unauthorised / transient
# wrong-tenant context) used to be indistinguishable from "the tenant has no groups", so the
# standard recreated every templated group on every run. Entra allows duplicate displayNames,
# so each missed match silently produced a twin (2 -> 4 -> 6 ...). The guard must create groups
# only when the read genuinely succeeds with no matching group present.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardGroupTemplate.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardGroupTemplate.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently landing
    # in $args.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $AsApp, $noPagination, $NoAuthCheck, $skipTokenCache, $Caller, [switch]$ComplexFilter, [switch]$CountOnly) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $scope, $AsApp, $NoAuthCheck, $skipTokenCache) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox) }
    function New-CIPPGroup { [CmdletBinding()] param($GroupObject, $TenantFilter, $APIName, $ExecutingUser) }
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter, $Property, $First) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData, $User) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    # Default no-op: only the variable-name tests mock this to actually substitute tokens.
    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables declared
    # there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:GroupName = 'CIPP-Test-Group'

    # A single generic (Graph) group template, stored the way Invoke-AddGroupTemplate persists it.
    function script:New-GenericTemplateEntity {
        [pscustomobject]@{
            RowKey = '11111111-1111-1111-1111-111111111111'
            JSON   = ([pscustomobject]@{
                    displayName     = $script:GroupName
                    description     = 'Test description'
                    groupType       = 'generic'
                    membershipRules = $null
                    GUID            = '11111111-1111-1111-1111-111111111111'
                } | ConvertTo-Json -Depth 10)
        }
    }

    # A dynamic distribution template - presence is checked against Exchange, not Graph.
    function script:New-DynamicDistroTemplateEntity {
        [pscustomobject]@{
            RowKey = '22222222-2222-2222-2222-222222222222'
            JSON   = ([pscustomobject]@{
                    displayName     = $script:GroupName
                    description     = 'Test description'
                    groupType       = 'dynamicDistribution'
                    membershipRules = "Alias -ne `$null"
                    GUID            = '22222222-2222-2222-2222-222222222222'
                } | ConvertTo-Json -Depth 10)
        }
    }

    # A generic template whose displayName carries a %tenantname% token, the way an operator writes
    # a per-tenant group name. New-GraphPostRequest resolves the token at creation time, so the real
    # group is named 'Contoso-Group'.
    $script:VariableGroupName = '%tenantname%-Group'
    $script:ResolvedGroupName = 'Contoso-Group'
    function script:New-VariableTemplateEntity {
        [pscustomobject]@{
            RowKey = '33333333-3333-3333-3333-333333333333'
            JSON   = ([pscustomobject]@{
                    displayName     = $script:VariableGroupName
                    description     = 'Test description'
                    groupType       = 'generic'
                    membershipRules = $null
                    GUID            = '33333333-3333-3333-3333-333333333333'
                } | ConvertTo-Json -Depth 10)
        }
    }

    function script:New-Settings {
        param([switch]$Remediate, [switch]$Report)
        [pscustomobject]@{
            remediate     = [bool]$Remediate
            report        = [bool]$Report
            groupTemplate = [pscustomobject]@{ value = '11111111-1111-1111-1111-111111111111' }
        }
    }

    # Settings for tiers merged into one run, shaped as the queue delivers them: one element per
    # contributing standards template, round-tripped through JSON.
    function script:New-MergedSettings {
        param([string[][]]$Selections)
        @(foreach ($Selection in $Selections) {
                @{
                    remediate     = $true
                    report        = $true
                    groupTemplate = @($Selection | ForEach-Object { @{ label = "Group $_"; value = $_ } })
                }
            }) | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'Invoke-CIPPStandardGroupTemplate' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Get-CippTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { script:New-GenericTemplateEntity }
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-GraphPostRequest -MockWith { $null }
        Mock -CommandName New-CIPPGroup -MockWith { [pscustomobject]@{ Success = $true; GroupId = 'new-group-id' } }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
    }

    Context 'existing groups can be read' {
        It 'does not recreate a group that already exists in the tenant' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'existing-id'; displayName = $script:GroupName; description = 'Test description'; membershipRule = $null })
            }

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Remediate)

            Should -Invoke -CommandName New-CIPPGroup -Times 0 -Exactly -Because 'the group already exists, so creating it would make a duplicate'
        }

        It 'creates the group when the tenant genuinely has none' {
            Mock -CommandName New-GraphGetRequest -MockWith { @() }

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Remediate)

            Should -Invoke -CommandName New-CIPPGroup -Times 1 -Exactly -Because 'an empty read with no error is a real empty tenant'
        }
    }

    Context 'template display name contains a %variable%' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { script:New-VariableTemplateEntity }
            # Resolve %tenantname% the way Get-CIPPTextReplacement does at runtime, so comparisons run
            # against the same name New-GraphPostRequest gives the real group.
            Mock -CommandName Get-CIPPTextReplacement -MockWith {
                param($TenantFilter, $Text, [switch]$EscapeForJson)
                $Text -replace '%tenantname%', 'Contoso'
            }
        }

        It 'does not recreate the group when the resolved-name group already exists' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'existing-id'; displayName = $script:ResolvedGroupName; description = 'Test description'; membershipRule = $null })
            }

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Remediate)

            Should -Invoke -CommandName New-CIPPGroup -Times 0 -Exactly -Because 'the group exists under its resolved name, so recreating it would make a duplicate'
        }

        It 'reports compliant when the resolved-name group exists' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @([pscustomobject]@{ id = 'existing-id'; displayName = $script:ResolvedGroupName; description = 'Test description'; membershipRule = $null })
            }

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Report)

            Should -Invoke -CommandName Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                @($CurrentValue.MissingGroups).Count -eq 0
            } -Because 'the resolved name matches an existing group, so nothing is missing'
        }
    }

    Context 'existing groups cannot be read' {
        It 'creates no groups when the Graph read fails, avoiding duplicate twins' {
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Request not authorised for tenant' }

            { Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Remediate) } |
                Should -Not -Throw

            Should -Invoke -CommandName New-CIPPGroup -Times 0 -Exactly -Because 'a failed read must not be treated as "no groups exist"'

            $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' })
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Message | Should -Match 'skipping this run to avoid creating duplicate groups'
        }

        It 'does not overwrite the compliance report as all-missing when the read fails' {
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'Request not authorised for tenant' }

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Report)

            Should -Invoke -CommandName Set-CIPPStandardsCompareField -Times 0 -Exactly -Because 'reporting every group as missing on a failed read produces false drift'
        }

    }

    Context 'dynamic distribution group templates are not supported' {
        # DDLs were removed from CIPP: EXO canonicalises RecipientFilter (permanent drift) and
        # Set-DynamicDistributionGroup -RecipientFilter throws. They must be skipped - never created,
        # never remediated - but the skip must be visible in the logs and in the report.
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { script:New-DynamicDistroTemplateEntity }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
            Mock -CommandName New-ExoRequest -MockWith { }
        }

        It 'skips a dynamic distribution template in remediate mode and logs a warning' {
            $Settings = [pscustomobject]@{
                remediate     = $true
                report        = $false
                groupTemplate = [pscustomobject]@{ value = '22222222-2222-2222-2222-222222222222' }
            }
            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings $Settings

            Should -Invoke -CommandName New-CIPPGroup -Times 0 -Exactly -Because 'DDLs are not supported and must not be created'
            Should -Invoke -CommandName New-ExoRequest -Times 0 -Exactly -Because 'Set-DynamicDistributionGroup must never run for a skipped DDL'

            $Warns = @($script:logs | Where-Object { $_.Sev -eq 'Warning' })
            $Warns.Count | Should -BeGreaterThan 0
            $Warns[0].Message | Should -Match 'Dynamic Distribution Group.*not supported by CIPP'
        }

        It 'surfaces a skipped dynamic distribution template in the report, not as drift' {
            $Settings = [pscustomobject]@{
                remediate     = $false
                report        = $true
                groupTemplate = [pscustomobject]@{ value = '22222222-2222-2222-2222-222222222222' }
            }
            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings $Settings

            Should -Invoke -CommandName Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                $null -ne $CurrentValue.SkippedDynamicDistributionGroups -and
                $CurrentValue.SkippedDynamicDistributionGroups -eq $ExpectedValue.SkippedDynamicDistributionGroups -and
                @($CurrentValue.MissingGroups).Count -eq 0 -and
                @($CurrentValue.MissingTemplates).Count -eq 0
            } -Because 'the DDL is reported as skipped/not-supported, identical on both sides so it shows without reading as drift'
        }
    }

    Context 'standards templates from several tiers merged into one run' {
        # The engine runs every template's Group Template instance as one standard, so Settings
        # arrives as one element per contributing standards template, with overlapping selections.
        BeforeEach {
            $script:GroupTemplateRows = @(
                foreach ($Id in 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000003') {
                    [pscustomobject]@{
                        RowKey = $Id
                        JSON   = (@{ displayName = "Group $Id"; description = 'Test description'; groupType = 'generic'; GUID = $Id } | ConvertTo-Json)
                    }
                }
            )
            # Behaves like the table service: answers the filter it is given and rejects a filter
            # with more than the 15 comparisons it allows, reporting it the way Get-CIPPAzDataTableEntity does.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($Filter)
                if ([regex]::Matches($Filter, ' eq ').Count -gt 15) {
                    Write-Error -Message 'The query filter has too many comparisons.'
                    return
                }
                $script:GroupTemplateRows | Where-Object { $Filter -notmatch 'RowKey' -or $Filter -match "RowKey eq '$($_.RowKey)'" }
            }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
        }

        It 'creates each selected group once' {
            $Settings = script:New-MergedSettings -Selections @(
                , @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002')
                , @('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000003')
                , @('aaaaaaaa-0000-0000-0000-000000000001')
            )

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings $Settings

            Should -Invoke -CommandName New-CIPPGroup -Times 3 -Exactly
            @($script:logs | Where-Object { $_.Message -match 'no longer exist' }).Count | Should -Be 0
        }

        It 'counts a missing template once, against the unique selection' {
            $Settings = script:New-MergedSettings -Selections @(
                , @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000dead')
                , @('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000dead')
            )

            Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings $Settings

            $Missing = @($script:logs | Where-Object { $_.Message -match 'no longer exist' })
            $Missing.Count | Should -Be 1
            $Missing[0].Message | Should -Match '1 of 2 selected group templates no longer exist \(ids: aaaaaaaa-0000-0000-0000-00000000dead\)'
        }
    }

    Context 'the template table cannot be read' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { Write-Error -Message 'The table service is unavailable.' }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
        }

        It 'logs the read failure and skips the run instead of calling the templates missing' {
            { Invoke-CIPPStandardGroupTemplate -Tenant $script:Tenant -Settings (script:New-Settings -Remediate -Report) } |
                Should -Not -Throw

            Should -Invoke -CommandName New-CIPPGroup -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPStandardsCompareField -Times 0 -Exactly -Because 'a failed read is not drift'
            @($script:logs | Where-Object { $_.Message -match 'no longer exist' }).Count | Should -Be 0
            @($script:logs | Where-Object { $_.Sev -eq 'Error' -and $_.Message -match 'could not read the group template table' }).Count | Should -Be 1
        }
    }
}
