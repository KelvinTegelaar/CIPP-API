BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippRequestAllowedPermissions { $script:CallerPermissions }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) $script:Rows | Where-Object { $Filter -match [regex]::Escape("'$($_.RowKey)'") -and ($Filter -notmatch 'PartitionKey' -or $Filter -match "'$($_.PartitionKey)'") } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Entity) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function ConvertTo-CIPPGSAFilteringRule { param($Rules) @{ Rules = @(); Errors = @() } }
    function ConvertTo-CIPPGSAProfileLink { param($Links) @{ Links = @(); Errors = @() } }
    function Get-CippErrorStatusCode {
        param($ErrorRecord)
        if ($ErrorRecord.Exception -is [System.UnauthorizedAccessException]) { return [System.Net.HttpStatusCode]::Forbidden }
        if ($ErrorRecord.Exception -is [System.Management.Automation.ItemNotFoundException]) { return [System.Net.HttpStatusCode]::NotFound }
        [System.Net.HttpStatusCode]::InternalServerError
    }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    $HelperPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Test-CippTemplateWriteAccess.ps1'
    if (Test-Path $HelperPath) { . $HelperPath }

    $script:HttpRoot = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    function Import-Endpoint($RelativePath) {
        $Path = Join-Path $script:HttpRoot $RelativePath
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Path -Raw)))
    }

    $script:TemplateId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Endpoint($Name, $Body) {
        & $Name -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = $Name -replace '^Invoke-' }
                Headers = @{}
                Query   = @{ ID = $script:TemplateId }
                Body    = [pscustomobject]$Body
            }) -TriggerMetadata $null
    }
    function Set-CallerScope([object]$Tenants) {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
        $script:CippAllowedTenantsStorage.Value = $Tenants
    }
}

Describe 'Test-CippTemplateWriteAccess' {
    BeforeEach {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.ConditionalAccess.ReadWrite')
        $script:Rows = @([pscustomobject]@{ PartitionKey = 'CATemplate'; RowKey = $script:TemplateId })
        Set-CallerScope $null
    }

    It 'allows callers outside an HTTP request (scheduler, standards)' {
        $script:CallerPermissions = $null
        Set-CallerScope @('tenant-1')
        Test-CippTemplateWriteAccess -Permission 'Endpoint.MEM.ReadWrite' | Should -BeTrue
    }

    It 'allows an unrestricted caller holding the permission' {
        Test-CippTemplateWriteAccess -Permission 'Tenant.ConditionalAccess.ReadWrite' | Should -BeTrue
    }

    It 'refuses a caller without the template type permission' {
        Test-CippTemplateWriteAccess -Permission 'Endpoint.MEM.ReadWrite' | Should -BeFalse
    }

    It 'refuses a tenant-restricted caller changing a template (<Scope>)' -ForEach @(
        @{ Scope = 'some tenants'; Tenants = @('tenant-1') }
        @{ Scope = 'no tenants'; Tenants = @() }
    ) {
        Set-CallerScope $Tenants
        Test-CippTemplateWriteAccess | Should -BeFalse
        Test-CippTemplateWriteAccess -PartitionKey 'CATemplate' -RowKey $script:TemplateId | Should -BeFalse
    }

    It 'lets a tenant-restricted caller create a new template' {
        Set-CallerScope @('tenant-1')
        Test-CippTemplateWriteAccess -PartitionKey 'CATemplate' -RowKey '22222222-2222-2222-2222-222222222222' | Should -BeTrue
        Test-CippTemplateWriteAccess -PartitionKey 'CATemplate' -RowKey '' | Should -BeTrue
        Test-CippTemplateWriteAccess -PartitionKey 'CATemplate' -RowKey $null | Should -BeTrue
    }
}

Describe '<Name> shared template writes' -ForEach @(
    @{ Name = 'Invoke-AddTransportTemplate'; Path = 'Email-Exchange/Transport/Invoke-AddTransportTemplate.ps1'; Partition = 'TransportTemplate'; Writer = 'Add-CIPPAzDataTableEntity'; Body = @{ PowerShellCommand = '{"name":"x"}' } }
    @{ Name = 'Invoke-EditTenantAllowBlockListTemplate'; Path = 'Email-Exchange/Spamfilter/Invoke-EditTenantAllowBlockListTemplate.ps1'; Partition = 'TenantAllowBlockListTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveTransportRuleTemplate'; Path = 'Email-Exchange/Transport/Invoke-RemoveTransportRuleTemplate.ps1'; Partition = 'TransportTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveTenantAllowBlockListTemplate'; Path = 'Email-Exchange/Spamfilter/Invoke-RemoveTenantAllowBlockListTemplate.ps1'; Partition = 'TenantAllowBlockListTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveExConnectorTemplate'; Path = 'Email-Exchange/Transport/Invoke-RemoveExConnectorTemplate.ps1'; Partition = 'ExConnectorTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-EditContactTemplates'; Path = 'Email-Exchange/Administration/Contacts/Invoke-EditContactTemplates.ps1'; Partition = 'ContactTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveContactTemplates'; Path = 'Email-Exchange/Administration/Contacts/Invoke-RemoveContactTemplates.ps1'; Partition = 'ContactTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddAppTemplate'; Path = 'Endpoint/Applications/Invoke-AddAppTemplate.ps1'; Partition = 'AppTemplate'; Writer = 'Add-CIPPAzDataTableEntity'; Body = @{ displayName = 'x'; apps = @(@{ appType = 'chocolateyApp'; appName = 'x'; config = '{}' }) } }
    @{ Name = 'Invoke-RemoveAppTemplate'; Path = 'Endpoint/Applications/Invoke-RemoveAppTemplate.ps1'; Partition = 'AppTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddEnrollmentRestrictionTemplate'; Path = 'Endpoint/Autopilot/Invoke-AddEnrollmentRestrictionTemplate.ps1'; Partition = 'EnrollmentRestrictionTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveEnrollmentRestrictionTemplate'; Path = 'Endpoint/Autopilot/Invoke-RemoveEnrollmentRestrictionTemplate.ps1'; Partition = 'EnrollmentRestrictionTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddAssignmentFilterTemplate'; Path = 'Endpoint/MEM/Invoke-AddAssignmentFilterTemplate.ps1'; Partition = 'AssignmentFilterTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveAssignmentFilterTemplate'; Path = 'Endpoint/MEM/Invoke-RemoveAssignmentFilterTemplate.ps1'; Partition = 'AssignmentFilterTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddIntuneReusableSettingTemplate'; Path = 'Endpoint/MEM/Invoke-AddIntuneReusableSettingTemplate.ps1'; Partition = 'IntuneReusableSettingTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveIntuneReusableSettingTemplate'; Path = 'Endpoint/MEM/Invoke-RemoveIntuneReusableSettingTemplate.ps1'; Partition = 'IntuneReusableSettingTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveIntuneTemplate'; Path = 'Endpoint/MEM/Invoke-RemoveIntuneTemplate.ps1'; Partition = 'IntuneTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddGroupTemplate'; Path = 'Identity/Administration/Groups/Invoke-AddGroupTemplate.ps1'; Partition = 'GroupTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveGroupTemplate'; Path = 'Identity/Administration/Groups/Invoke-RemoveGroupTemplate.ps1'; Partition = 'GroupTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddPIMRoleSettingsTemplate'; Path = 'Identity/Administration/Roles/Invoke-AddPIMRoleSettingsTemplate.ps1'; Partition = 'PIMRoleSettingsTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemovePIMRoleSettingsTemplate'; Path = 'Identity/Administration/Roles/Invoke-RemovePIMRoleSettingsTemplate.ps1'; Partition = 'PIMRoleSettingsTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveDlpCompliancePolicyTemplate'; Path = 'Security/Compliance-DLP/Invoke-RemoveDlpCompliancePolicyTemplate.ps1'; Partition = 'DlpCompliancePolicyTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveRetentionCompliancePolicyTemplate'; Path = 'Security/Compliance-Retention/Invoke-RemoveRetentionCompliancePolicyTemplate.ps1'; Partition = 'RetentionCompliancePolicyTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveSensitiveInfoTypeTemplate'; Path = 'Security/Compliance-SIT/Invoke-RemoveSensitiveInfoTypeTemplate.ps1'; Partition = 'SensitiveInfoTypeTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveSensitivityLabelTemplate'; Path = 'Security/Compliance-SensitivityLabel/Invoke-RemoveSensitivityLabelTemplate.ps1'; Partition = 'SensitivityLabelTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-EditSafeLinksPolicyTemplate'; Path = 'Security/Safe-Links-Policy/Invoke-EditSafeLinksPolicyTemplate.ps1'; Partition = 'SafeLinksTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveSafeLinksPolicyTemplate'; Path = 'Security/Safe-Links-Policy/Invoke-RemoveSafeLinksPolicyTemplate.ps1'; Partition = 'SafeLinksTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveCATemplate'; Path = 'Tenant/Conditional/Invoke-RemoveCATemplate.ps1'; Partition = 'CATemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddGSAFilteringPolicyTemplate'; Path = 'Tenant/GlobalSecureAccess/Invoke-AddGSAFilteringPolicyTemplate.ps1'; Partition = 'GSAFilteringPolicyTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-AddGSASecurityProfileTemplate'; Path = 'Tenant/GlobalSecureAccess/Invoke-AddGSASecurityProfileTemplate.ps1'; Partition = 'GSASecurityProfileTemplate'; Writer = 'Add-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveGSAFilteringPolicyTemplate'; Path = 'Tenant/GlobalSecureAccess/Invoke-RemoveGSAFilteringPolicyTemplate.ps1'; Partition = 'GSAFilteringPolicyTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveGSASecurityProfileTemplate'; Path = 'Tenant/GlobalSecureAccess/Invoke-RemoveGSASecurityProfileTemplate.ps1'; Partition = 'GSASecurityProfileTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveSpamfilterTemplate'; Path = 'Email-Exchange/Spamfilter/Invoke-RemoveSpamfilterTemplate.ps1'; Partition = 'SpamfilterTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-RemoveConnectionfilterTemplate'; Path = 'Email-Exchange/Spamfilter/Invoke-RemoveConnectionfilterTemplate.ps1'; Partition = 'ConnectionfilterTemplate'; Writer = 'Remove-CIPPAzDataTableEntity' }
    @{ Name = 'Invoke-ExecAppApprovalTemplate'; Path = 'Tenant/Administration/Application Approval/Invoke-ExecAppApprovalTemplate.ps1'; Partition = 'AppApprovalTemplate'; Writer = 'Add-CIPPAzDataTableEntity'; Body = @{ Action = 'Save'; TemplateId = '11111111-1111-1111-1111-111111111111'; TemplateName = 'x' } }
    @{ Name = 'Invoke-ExecAppApprovalTemplate'; Path = 'Tenant/Administration/Application Approval/Invoke-ExecAppApprovalTemplate.ps1'; Partition = 'AppApprovalTemplate'; Writer = 'Remove-CIPPAzDataTableEntity'; Body = @{ Action = 'Delete'; TemplateId = '11111111-1111-1111-1111-111111111111' } }
) {
    BeforeAll { . Import-Endpoint $Path }
    BeforeEach {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite')
        $script:Rows = @([pscustomobject]@{ PartitionKey = $Partition; RowKey = $script:TemplateId; JSON = '{"name":"x","displayName":"x","templateName":"x"}' })
        $script:RequestBody = @{ ID = $script:TemplateId; GUID = $script:TemplateId } + ($Body ?? @{})
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Remove-AzDataTableEntity { }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'refuses a tenant-restricted caller changing an existing template' {
        Set-CallerScope @('tenant-1')
        (Invoke-Endpoint $Name $script:RequestBody).StatusCode | Should -Be 403
        Should -Invoke $Writer -Times 0
    }

    It 'does not refuse an unrestricted caller' {
        Set-CallerScope $null
        (Invoke-Endpoint $Name $script:RequestBody).StatusCode | Should -Not -Be 403
    }
}

Describe 'Tenant-restricted callers creating templates' {
    BeforeAll { . Import-Endpoint 'Email-Exchange/Transport/Invoke-AddTransportTemplate.ps1' }
    BeforeEach {
        $script:CallerPermissions = @('Exchange.TransportRule.ReadWrite')
        $script:Rows = @([pscustomobject]@{ PartitionKey = 'TransportTemplate'; RowKey = $script:TemplateId })
        Set-CallerScope @('tenant-1')
        Mock Add-CIPPAzDataTableEntity { }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'saves a rule under a GUID that is not an existing template' {
        (Invoke-Endpoint 'Invoke-AddTransportTemplate' @{ GUID = '33333333-3333-3333-3333-333333333333'; PowerShellCommand = '{"name":"x"}' }).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }

    It 'saves a tenant rule as a new template even when its Guid matches a template' {
        (Invoke-Endpoint 'Invoke-AddTransportTemplate' @{ Guid = $script:TemplateId; Name = 'x' }).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }

    It 'saves a template with no GUID' {
        (Invoke-Endpoint 'Invoke-AddTransportTemplate' @{ name = 'x' }).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }
}

Describe 'Invoke-ExecCloneTemplate' {
    BeforeAll { . Import-Endpoint 'CIPP/Core/Invoke-ExecCloneTemplate.ps1' }
    BeforeEach {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite')
        Set-CallerScope $null
        Mock Add-CIPPAzDataTableEntity { }
    }

    It 'refuses to clone a <Type> row' -ForEach @(
        @{ Type = 'StandardsTemplateV2' }
        @{ Type = 'GroupTemplate' }
    ) {
        $script:Rows = @([pscustomobject]@{ PartitionKey = $Type; RowKey = $script:TemplateId; JSON = '{}' })
        (Invoke-Endpoint 'Invoke-ExecCloneTemplate' @{ GUID = $script:TemplateId; Type = $Type }).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'clones a <Type> row' -ForEach @(
        @{ Type = 'CATemplate' }
        @{ Type = 'IntuneTemplate' }
    ) {
        $script:Rows = @([pscustomobject]@{ PartitionKey = $Type; RowKey = $script:TemplateId; JSON = '{}' })
        (Invoke-Endpoint 'Invoke-ExecCloneTemplate' @{ GUID = $script:TemplateId; Type = $Type }).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }
}

Describe 'Invoke-ExecSetPackageTag' {
    BeforeAll { . Import-Endpoint 'CIPP/Core/Invoke-ExecSetPackageTag.ps1' }
    BeforeEach {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.ConditionalAccess.ReadWrite')
        $script:Rows = @([pscustomobject]@{ PartitionKey = 'CATemplate'; RowKey = $script:TemplateId; JSON = '{}' })
        Set-CallerScope $null
        Mock Add-CIPPAzDataTableEntity { }
    }
    AfterAll { $script:CippAllowedTenantsStorage = $null }

    It 'tags a template the caller holds the permission for' {
        (Invoke-Endpoint 'Invoke-ExecSetPackageTag' @{ GUID = @($script:TemplateId); Package = 'Pkg' }).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq 'CATemplate' -and $Entity.Package -eq 'Pkg' }
    }

    It 'refuses a caller without the template type permission' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite')
        (Invoke-Endpoint 'Invoke-ExecSetPackageTag' @{ GUID = @($script:TemplateId); Package = 'Pkg' }).StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses a tenant-restricted caller' {
        Set-CallerScope @('tenant-1')
        (Invoke-Endpoint 'Invoke-ExecSetPackageTag' @{ GUID = @($script:TemplateId); Remove = $true }).StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'does not tag a standards template' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.Standards.ReadWrite')
        $script:Rows = @([pscustomobject]@{ PartitionKey = 'StandardsTemplateV2'; RowKey = $script:TemplateId; JSON = '{}' })
        (Invoke-Endpoint 'Invoke-ExecSetPackageTag' @{ GUID = @($script:TemplateId); Package = 'Pkg' }).StatusCode | Should -Be 404
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
