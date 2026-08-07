BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyReport.ps1')

    function New-IntunePolicyDbItem {
        param(
            [string]$Tenant,
            [string]$Type,
            $Data,
            [DateTimeOffset]$Timestamp = [DateTimeOffset]::UtcNow
        )

        [PSCustomObject]@{
            PartitionKey = $Tenant
            RowKey       = "$Type-$($Data.id)"
            Timestamp    = $Timestamp
            Data         = $Data | ConvertTo-Json -Depth 10 -Compress -WarningAction SilentlyContinue
        }
    }
}

Describe 'Get-CIPPIntunePolicyReport' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'
        $script:Definitions = @(Get-CIPPIntunePolicyListDefinitions)
        $script:RowsByType = @{}
        $script:Timestamp = [DateTimeOffset]::UtcNow
        $script:IntuneGroupItems = @(
            New-IntunePolicyDbItem -Tenant $script:Tenant -Type 'IntunePolicyGroups' -Data ([PSCustomObject]@{
                    id          = 'group-1'
                    displayName = 'Current group name'
                }) -Timestamp $script:Timestamp
        )

        foreach ($Definition in $script:Definitions) {
            $Policy = [PSCustomObject]@{
                id          = "$($Definition.Id)-1"
                displayName = "$($Definition.Id) policy"
                assignments = @(
                    [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId       = 'group-1'
                        }
                    }
                )
            }
            if ($Definition.Id -eq 'ManagedAppPolicies') {
                $Policy | Add-Member -NotePropertyName '@odata.type' -NotePropertyValue '#microsoft.graph.iosManagedAppProtection'
            }

            $script:RowsByType[$Definition.CacheType] = @(
                New-IntunePolicyDbItem -Tenant $script:Tenant -Type $Definition.CacheType -Data $Policy -Timestamp $script:Timestamp
            )
        }

        $ConfigurationType = ($script:Definitions | Where-Object Id -eq 'ConfigurationPolicies').CacheType
        $script:RowsByType[$ConfigurationType] += @(
            New-IntunePolicyDbItem -Tenant $script:Tenant -Type $ConfigurationType -Data ([PSCustomObject]@{
                    id          = 'linux-policy'
                    displayName = 'Linux policy'
                    platforms   = 'linux'
                }) -Timestamp $script:Timestamp
            New-IntunePolicyDbItem -Tenant $script:Tenant -Type $ConfigurationType -Data ([PSCustomObject]@{
                    id                = 'script-policy'
                    displayName       = 'Script policy'
                    templateReference = [PSCustomObject]@{ templateFamily = 'deviceConfigurationScripts' }
                }) -Timestamp $script:Timestamp
        )

        Mock Write-LogMessage {}
        Mock Get-Tenants {
            @([PSCustomObject]@{ defaultDomainName = $script:Tenant })
        }
        Mock Get-CIPPDbItem {
            if ($Type -eq 'Groups') {
                return @(New-IntunePolicyDbItem -Tenant $script:Tenant -Type 'Groups' -Data ([PSCustomObject]@{
                            id          = 'group-1'
                            displayName = 'Old group name'
                        }) -Timestamp $script:Timestamp)
            }
            if ($Type -eq 'IntunePolicyGroups') {
                return @($script:IntuneGroupItems)
            }
            return @($script:RowsByType[$Type])
        }
    }

    It 'returns every live policy family with the shared normalization' {
        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter $script:Tenant)

        $Result | Should -HaveCount 11
        $Result.id | Should -Contain 'deviceCompliancePolicies-1'
        $Result.id | Should -Contain 'Intents-1'
        $Result.id | Should -Contain 'ManagedAppPolicies-1'
        $Result.URLName | Sort-Object | Should -Be ($script:Definitions.Id | Sort-Object)
        ($Result | Where-Object id -eq 'Intents-1').PolicyTypeName | Should -Be 'Endpoint Security'
        ($Result | Where-Object id -eq 'ManagedAppPolicies-1').PolicyTypeName | Should -Be 'iOS App Protection'
        $Result.PolicyAssignment | Select-Object -Unique | Should -Be 'Current group name'
        $Result.CacheTimestamp | Select-Object -Unique | Should -Be $script:Timestamp
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -eq 'Groups' }
    }

    It 'adds Tenant for AllTenants and excludes cache timestamp metadata' {
        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter 'AllTenants')

        $Result | Should -HaveCount 11
        $Result.Tenant | Select-Object -Unique | Should -Be $script:Tenant
        $Result[0].PSObject.Properties.Name | Should -Not -Contain 'CacheTimestamp'
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -eq 'Groups' }
    }

    It 'falls back to the normal Groups cache when no Intune snapshot exists' {
        $script:IntuneGroupItems = @()

        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter $script:Tenant)

        $Result | Should -HaveCount 11
        $Result.PolicyAssignment | Select-Object -Unique | Should -Be 'Old group name'
        Should -Invoke Get-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq $script:Tenant -and $Type -eq 'Groups'
        }
    }

    It 'treats a count-only Intune snapshot as authoritative' {
        $script:IntuneGroupItems = @(
            [PSCustomObject]@{
                PartitionKey = $script:Tenant
                RowKey       = 'IntunePolicyGroups-Count'
                Timestamp    = $script:Timestamp
                DataCount    = 0
            }
        )

        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter $script:Tenant)

        $Result | Should -HaveCount 11
        $Result.PolicyAssignment | Select-Object -Unique | Should -Be ''
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -eq 'Groups' }
    }

    It 'returns a configuration policy whose cached settings exceed JSON depth 10' {
        $NestedSetting = [PSCustomObject]@{ value = 'leaf' }
        foreach ($Level in 1..12) {
            $NestedSetting = [PSCustomObject]@{ child = $NestedSetting }
        }

        $ConfigurationType = ($script:Definitions | Where-Object Id -eq 'ConfigurationPolicies').CacheType
        $DeepPolicyRow = New-IntunePolicyDbItem -Tenant $script:Tenant -Type $ConfigurationType -Data ([PSCustomObject]@{
                id          = 'deep-settings-policy'
                displayName = 'Deep settings policy'
                settings    = @($NestedSetting)
                assignments = @(
                    [PSCustomObject]@{
                        target = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId       = 'group-1'
                        }
                    }
                )
            }) -Timestamp $script:Timestamp

        { $DeepPolicyRow.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop } | Should -Throw
        $script:RowsByType[$ConfigurationType] += $DeepPolicyRow

        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter $script:Tenant)
        $DeepPolicy = $Result | Where-Object id -eq 'deep-settings-policy'

        $Result | Should -HaveCount 12
        $DeepPolicy | Should -Not -BeNullOrEmpty
        $DeepPolicy.URLName | Should -Be 'ConfigurationPolicies'
        $DeepPolicy.PolicyTypeName | Should -Be 'Device Configuration'
        $DeepPolicy.PolicyAssignment | Should -Be 'Current group name'
    }

    It 'logs and skips only the malformed cached policy row' {
        $ConfigurationType = ($script:Definitions | Where-Object Id -eq 'ConfigurationPolicies').CacheType
        $script:RowsByType[$ConfigurationType] += [PSCustomObject]@{
            PartitionKey = $script:Tenant
            RowKey       = "$ConfigurationType-malformed-policy"
            Timestamp    = $script:Timestamp
            Data         = '{malformed-json'
        }

        $Result = @(Get-CIPPIntunePolicyReport -TenantFilter $script:Tenant)

        $Result | Should -HaveCount 11
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $API -eq 'IntunePolicyReport' -and
            $tenant -eq $script:Tenant -and
            $sev -eq 'Warning' -and
            $message -like "*$ConfigurationType*" -and
            $message -like '*malformed-policy*'
        }
    }
}
