# Endpoints that act on a stored row by its key, or list a whole table, must keep a tenant-restricted
# caller to their own tenants' rows. The router never sees the row's tenant, so each endpoint checks it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    $script:AllTenants = @(
        [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 'contoso.com' }
        [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 'fabrikam.com' }
    )
    function Get-Tenants {
        param($TenantFilter, [switch]$IncludeErrors)
        $script:AllTenants.Where({
                ($null -eq $script:CippAllowedTenantsStorage.Value -or $script:CippAllowedTenantsStorage.Value -contains $_.customerId) -and
                (-not $TenantFilter -or $TenantFilter -in @($_.customerId, $_.defaultDomainName))
            })
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) $script:Rows }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-CIPPScheduledTask { param($Task, $Headers, $Hidden, $DisallowDuplicateName, $DesiredStartTime, $RowKey, [switch]$RunNow) 'queued' }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData, $tenant) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($message) $message }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:CippAllowedTenantsStorage.Value ?? @('AllTenants') }
    function Add-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-AzDataTableEntity { param($TableName, $Filter) $script:Rows }
    function New-CIPPStandardsRun { param($TenantFilter, $TemplateID, $runManually, [switch]$Force) 'instance' }
    # Request-scoped like the real one: a group outside the caller's groups is invisible.
    function Get-TenantGroups {
        param($GroupId)
        if ($script:CippAllowedGroupsStorage.Value -and $script:CippAllowedGroupsStorage.Value -notcontains $GroupId) { return }
        [pscustomobject]@{ Id = $GroupId; members = @([pscustomobject]@{ customerId = 'tenant-2' }) }
    }
    # Stands in for the dispatcher decision: resolves each target by its value, never by addedFields.
    function Assert-CippTenantAccess {
        param($Request, $TenantFilter)
        if ($null -eq $script:RoleTenants) { return }
        foreach ($Item in @($TenantFilter)) {
            if ($null -eq $Item) { continue }
            $Value = $Item.value ?? $Item
            $Ok = if ($Item.type -eq 'Group') { $script:RoleGroups -contains $Value } else {
                $script:RoleTenants -contains $script:AllTenants.Where({ $Value -in @($_.customerId, $_.defaultDomainName) }, 'First')[0].customerId
            }
            if (-not $Ok) { throw [System.UnauthorizedAccessException]::new("Your roles don't include $Value.") }
        }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Select-CippAllowedTenantData.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Test-CippTenantInScope.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Expand-CIPPTenantGroups.ps1')
    $Http = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    foreach ($Path in @(
            'Endpoint/Applications/Invoke-RemoveQueuedApp.ps1'
            'Endpoint/Applications/Invoke-ListApplicationQueue.ps1'
            'Tenant/Administration/Alerts/Invoke-RemoveQueuedAlert.ps1'
            'Tenant/Administration/Alerts/Invoke-ExecToggleAlert.ps1'
            'Tenant/Administration/Alerts/Invoke-AddAlert.ps1'
            'CIPP/Scheduler/Invoke-AddScheduledItem.ps1'
            'Tools/Report-Builder/Invoke-ExecGenerateReportBuilderReport.ps1'
            'CIPP/Settings/Invoke-ListIPWhitelist.ps1'
            'Tenant/Administration/Tenant/Invoke-EditTenantOffboardingDefaults.ps1'
            'CIPP/Settings/Invoke-ExecUserBookmarks.ps1'
            'CIPP/Settings/Invoke-ExecUserSettings.ps1'
            'Tenant/Standards/Invoke-AddStandardsTemplate.ps1'
            'Tenant/Standards/Invoke-ExecStandardConvert.ps1'
            'Tenant/Standards/Invoke-RemoveStandardTemplate.ps1'
            'Tenant/Standards/Invoke-ExecStandardTemplateSchedule.ps1'
            'Tenant/Standards/Invoke-ExecStandardsRun.ps1'
        )) {
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $Http $Path) -Raw)))
    }

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"me@contoso.com"}'))
    function Send($Endpoint, $Body, $Query = @{}) {
        & $Endpoint -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'Test' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Query = $Query; Body = [pscustomobject]$Body })
    }
    $Id = '11111111-1111-1111-1111-111111111111'
}

Describe 'stored row tenant scope' {
    BeforeEach {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        $script:CippAllowedGroupsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedGroupsStorage.Value = @('group-1')
        $script:RoleTenants = @('tenant-1')
        $script:RoleGroups = @('group-1')
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Update-AzDataTableEntity { }
        Mock Add-CIPPScheduledTask { 'queued' }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null; $script:CippAllowedGroupsStorage = $null }

    Context 'Test-CippTenantInScope' {
        It 'is <Expected> for <Name>' -ForEach @(
            @{ Name = 'an own domain'; Tenant = 'contoso.com'; Expected = $true }
            @{ Name = 'an own customerId'; Tenant = 'tenant-1'; Expected = $true }
            @{ Name = 'another tenant'; Tenant = 'fabrikam.com'; Expected = $false }
            @{ Name = 'All Tenants'; Tenant = 'AllTenants'; Expected = $false }
            @{ Name = 'a group selector'; Tenant = @(@{ value = 'group-1'; type = 'Group' }); Expected = $false }
            @{ Name = 'a list with one foreign tenant'; Tenant = @(@{ value = 'contoso.com' }, @{ value = 'fabrikam.com' }); Expected = $false }
            @{ Name = 'own selectors'; Tenant = @(@{ value = 'contoso.com' }); Expected = $true }
        ) {
            Test-CippTenantInScope -Tenant $Tenant | Should -Be $Expected
        }

        It 'lets an unrestricted caller through for any tenant' {
            $script:CippAllowedTenantsStorage.Value = $null
            Test-CippTenantInScope -Tenant 'AllTenants' | Should -BeTrue
            Test-CippTenantInScope -Tenant @(@{ value = 'fabrikam.com' }) | Should -BeTrue
        }
    }

    Context 'RemoveQueuedApp' {
        It 'does not remove another tenant''s queued app' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'apps'; RowKey = $Id; JSON = '{"tenant":"fabrikam.com"}' }
            (Send Invoke-RemoveQueuedApp @{ ID = $Id }).StatusCode | Should -Be 404
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
        }
        It 'removes the caller''s own queued app' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'apps'; RowKey = $Id; JSON = '{"tenant":"contoso.com"}' }
            (Send Invoke-RemoveQueuedApp @{ ID = $Id }).StatusCode | Should -Be 200
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1
        }
    }

    It 'ListApplicationQueue lists only the caller''s tenants' {
        $script:Rows = @(
            [pscustomobject]@{ RowKey = '1'; JSON = '{"tenant":"contoso.com","applicationName":"A"}' }
            [pscustomobject]@{ RowKey = '2'; JSON = '{"tenant":"fabrikam.com","applicationName":"B"}' }
        )
        @((Send Invoke-ListApplicationQueue @{}).Body).tenantName | Should -Be @('contoso.com')
    }

    Context '<Endpoint>' -ForEach @(
        @{ Endpoint = 'Invoke-RemoveQueuedAlert'; Writer = 'Remove-CIPPAzDataTableEntity' }
        @{ Endpoint = 'Invoke-ExecToggleAlert'; Writer = 'Update-AzDataTableEntity' }
    ) {
        It 'refuses an audit log alert that targets another tenant' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'Webhookv2'; RowKey = $Id; Tenants = '[{"value":"contoso.com"},{"value":"fabrikam.com"}]' }
            (Send $Endpoint @{ ID = $Id; EventType = 'Audit log Alert'; Disabled = 'true' }).StatusCode | Should -Be 403
            Should -Invoke $Writer -Times 0
        }
        It 'refuses an All Tenants scheduled alert' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = $Id; Tenant = 'AllTenants' }
            (Send $Endpoint @{ ID = $Id; EventType = 'Scheduled Task'; Disabled = 'true' }).StatusCode | Should -Be 403
            Should -Invoke $Writer -Times 0
        }
        It 'acts on the caller''s own alert' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'Webhookv2'; RowKey = $Id; Tenants = '[{"value":"contoso.com"}]' }
            (Send $Endpoint @{ ID = $Id; EventType = 'Audit log Alert'; Disabled = 'true' }).StatusCode | Should -Be 200
            Should -Invoke $Writer -Times 1
        }
    }

    Context 'AddAlert' {
        It 'refuses to overwrite another tenant''s audit log alert' {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; Tenants = '[{"value":"fabrikam.com"}]' }
            (Send Invoke-AddAlert @{ RowKey = $Id; tenantFilter = @(@{ value = 'contoso.com' }); conditions = @(); actions = @() }).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }
        It 'edits the caller''s own alert' {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; Tenants = '[{"value":"contoso.com"}]' }
            (Send Invoke-AddAlert @{ RowKey = $Id; tenantFilter = @(@{ value = 'contoso.com' }); conditions = @(); actions = @() }).StatusCode | Should -Be 200
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        }
    }

    Context 'AddScheduledItem' {
        It 'refuses to <Name> another tenant''s task' -ForEach @(
            @{ Name = 'run'; RunNow = $true }
            @{ Name = 'overwrite'; RunNow = $false }
        ) {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = $Id; Tenant = 'fabrikam.com' }
            (Send Invoke-AddScheduledItem @{ RowKey = $Id; RunNow = $RunNow; tenantFilter = @{ value = 'contoso.com' } }).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPScheduledTask -Times 0
            Should -Invoke Update-AzDataTableEntity -Times 0
        }
        It 'edits the caller''s own task' {
            $script:Rows = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = $Id; Tenant = 'contoso.com' }
            (Send Invoke-AddScheduledItem @{ RowKey = $Id; tenantFilter = @{ value = 'contoso.com' } }).StatusCode | Should -Be 200
            Should -Invoke Add-CIPPScheduledTask -Times 1
        }
    }

    It 'ExecGenerateReportBuilderReport does not delete another tenant''s report' {
        $script:Rows = [pscustomobject]@{ PartitionKey = 'fabrikam.com'; RowKey = $Id }
        (Send Invoke-ExecGenerateReportBuilderReport @{ Action = 'delete'; ReportGUID = $Id }).StatusCode | Should -Be 404
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'ListIPWhitelist shows All Tenants entries and the caller''s own, not other tenants''' {
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = '1.1.1.1'; Range = '1.1.1.1' }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '2.2.2.2'; Range = '2.2.2.2' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; RowKey = '3.3.3.3'; Range = '3.3.3.3' }
        )
        @((Send Invoke-ListIPWhitelist @{}).Body).PartitionKey | Should -Be @('AllTenants', 'contoso.com')
    }

    It 'clearing offboarding defaults ignores a domain from the body' {
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'OffboardingDefaults' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; RowKey = 'OffboardingDefaults' }
        )
        $null = Send Invoke-EditTenantOffboardingDefaults @{ customerId = 'tenant-1'; defaultDomainName = 'fabrikam.com'; offboardingDefaults = $null }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PartitionKey -eq 'contoso.com' }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $Entity.PartitionKey -eq 'fabrikam.com' }
    }

    Context 'user settings and bookmarks' {
        It 'saves bookmarks for the signed-in user whatever the body names' {
            $null = Send Invoke-ExecUserBookmarks @{ user = 'someone@else.com'; currentSettings = @{ bookmarks = @() } }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'me@contoso.com' }
        }
        It 'saves settings as <Saved> when the body names <User>' -ForEach @(
            @{ User = 'someone@else.com'; Saved = 'me@contoso.com' }
            @{ User = 'allUsers'; Saved = 'allUsers' }
        ) {
            $null = Send Invoke-ExecUserSettings @{ user = $User; currentSettings = @{ theme = 'dark' } }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq $Saved }
        }
    }

    Context 'AddStandardsTemplate' {
        BeforeEach { $script:Rows = $null }
        It 'refuses <Name>' -ForEach @(
            @{ Name = 'a tenant whose customerId is spoofed to an allowed one'; Filter = @(@{ value = 'fabrikam.com'; type = 'Tenant'; addedFields = @{ customerId = 'tenant-1' } }) }
            @{ Name = 'a tenant group outside the caller''s groups'; Filter = @(@{ value = 'group-2'; type = 'Group'; label = 'Other' }) }
            @{ Name = 'All Tenants'; Filter = @(@{ value = 'AllTenants'; type = 'Tenant' }) }
        ) {
            (Send Invoke-AddStandardsTemplate @{ templateName = 'T'; tenantFilter = $Filter }).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }
        It 'refuses to overwrite a template that targets tenants outside the caller''s access' {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = '{"tenantFilter":[{"value":"AllTenants"}]}' }
            (Send Invoke-AddStandardsTemplate @{ GUID = $Id; templateName = 'T'; tenantFilter = @(@{ value = 'contoso.com'; type = 'Tenant' }) }).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }
        It 'saves the caller''s own tenant and group' {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = '{"tenantFilter":[{"value":"contoso.com"}]}' }
            (Send Invoke-AddStandardsTemplate @{ GUID = $Id; templateName = 'T'; tenantFilter = @(@{ value = 'contoso.com'; type = 'Tenant'; addedFields = @{ customerId = 'tenant-1' } }, @{ value = 'group-1'; type = 'Group' }) }).StatusCode | Should -Be 200
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        }
        It 'lets a restricted caller assign their tenant to a template imported with the placeholder' {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = '{"tenantFilter":[{"label":"Template Tenant","value":"Template Tenant"}]}' }
            (Send Invoke-AddStandardsTemplate @{ GUID = $Id; templateName = 'T'; tenantFilter = @(@{ value = 'contoso.com'; type = 'Tenant' }) }).StatusCode | Should -Be 200
        }
        It 'lets an unrestricted caller assign All Tenants, any group and any tenant' {
            $script:CippAllowedTenantsStorage.Value = $null
            $script:CippAllowedGroupsStorage.Value = $null
            $script:RoleTenants = $null
            (Send Invoke-AddStandardsTemplate @{ templateName = 'T'; tenantFilter = @(@{ value = 'AllTenants' }, @{ value = 'group-2'; type = 'Group' }, @{ value = 'fabrikam.com' }) }).StatusCode | Should -Be 200
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        }
    }

    Context 'ExecStandardConvert' {
        BeforeEach { $script:Rows = [pscustomobject]@{ PartitionKey = 'standards'; RowKey = 'AllTenants'; JSON = '{"Tenant":"AllTenants","Standards":{"AuditLog":{"remediate":true}}}' } }
        It 'refuses a tenant-restricted caller' {
            (Send Invoke-ExecStandardConvert @{}).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
        }
        It 'converts for an unrestricted caller' {
            $script:CippAllowedTenantsStorage.Value = $null
            (Send Invoke-ExecStandardConvert @{}).StatusCode | Should -Be 200
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        }
    }

    Context '<Endpoint>' -ForEach @(
        @{ Endpoint = 'Invoke-RemoveStandardTemplate'; Body = @{ ID = '11111111-1111-1111-1111-111111111111' } }
        @{ Endpoint = 'Invoke-ExecStandardTemplateSchedule'; Body = @{ TemplateId = '11111111-1111-1111-1111-111111111111'; runManually = $false } }
    ) {
        It 'refuses a template that targets <Name>' -ForEach @(
            @{ Name = 'another tenant'; Filter = '[{"value":"fabrikam.com"}]' }
            @{ Name = 'All Tenants'; Filter = '[{"value":"AllTenants"}]' }
            @{ Name = 'a group outside the caller''s groups'; Filter = '[{"value":"contoso.com"},{"value":"group-2","type":"Group"}]' }
        ) {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = "{`"templateName`":`"T`",`"tenantFilter`":$Filter}" }
            (Send $Endpoint $Body).StatusCode | Should -Be 403
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
        }
        It 'acts on <Name>' -ForEach @(
            @{ Name = 'the caller''s own template'; Filter = '[{"value":"contoso.com"}]' }
            @{ Name = 'a template that only holds the import placeholder'; Filter = '[{"value":"Template Tenant"}]' }
        ) {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = "{`"templateName`":`"T`",`"tenantFilter`":$Filter}" }
            (Send $Endpoint $Body).StatusCode | Should -Be 200
        }
        It 'acts on any template for an unrestricted caller' {
            $script:RoleTenants = $null
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = '{"templateName":"T","tenantFilter":[{"value":"AllTenants"}]}' }
            (Send $Endpoint $Body).StatusCode | Should -Be 200
        }
    }

    Context 'ExecStandardsRun' {
        BeforeEach {
            $script:Rows = [pscustomobject]@{ RowKey = $Id; JSON = "{`"guid`":`"$Id`",`"templateName`":`"T`",`"tenantFilter`":[{`"value`":`"AllTenants`"}]}" }
            Mock New-CIPPStandardsRun { 'instance' }
        }
        It 'refuses a run with <Name>' -ForEach @(
            @{ Name = 'a template id and no tenant'; Query = @{ templateId = '11111111-1111-1111-1111-111111111111' } }
            @{ Name = 'no parameters'; Query = @{} }
        ) {
            (Send Invoke-ExecStandardsRun @{} $Query).StatusCode | Should -Be 403
            Should -Invoke New-CIPPStandardsRun -Times 0
        }
        It 'runs for the caller''s own tenant' {
            (Send Invoke-ExecStandardsRun @{} @{ templateId = $Id; tenantFilter = 'contoso.com' }).StatusCode | Should -Be 200
            Should -Invoke New-CIPPStandardsRun -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        }
        It 'runs across all tenants for an unrestricted caller' {
            $script:RoleTenants = $null
            (Send Invoke-ExecStandardsRun @{} @{ templateId = $Id }).StatusCode | Should -Be 200
            Should -Invoke New-CIPPStandardsRun -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' }
        }
    }
}
