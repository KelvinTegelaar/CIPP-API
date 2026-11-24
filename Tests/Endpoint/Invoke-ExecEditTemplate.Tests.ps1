BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, $OperationType) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    function Get-CippRequestAllowedPermissions { $script:CallerPermissions }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) if ($Filter -match "'template-1'") { $script:Row ?? [pscustomobject]@{ RowKey = 'template-1' } } }
    function Set-CIPPIntuneTemplate { param($RawJSON, $GUID, $DisplayName, $Description, $templateType, $Package, $Headers, [switch]$PayloadChanged, $ReusableSettings, [hashtable]$Metadata) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Test-CippTemplateWriteAccess.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecEditTemplate.ps1')

    function Invoke-Edit($Type) {
        Invoke-ExecEditTemplate -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEditTemplate' }
                Headers = @{}
                Query   = @{ Type = $Type }
                Body    = [pscustomobject]@{ GUID = 'template-1'; displayName = 'x' }
            })
    }
}

Describe 'Invoke-ExecEditTemplate template types' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity { } }

    It 'refuses to write a <Type> template' -ForEach @(
        @{ Type = 'StandardsTemplateV2' }
        @{ Type = 'GroupTemplate' }
        @{ Type = $null }
    ) {
        (Invoke-Edit $Type).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'saves a CATemplate' {
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq 'CATemplate' }
    }
}

Describe 'Invoke-ExecEditTemplate caller access' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity { }
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    AfterEach { $script:CallerPermissions = $null; $script:CippAllowedTenantsStorage = $null }

    It 'refuses a caller without Tenant.ConditionalAccess.ReadWrite' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite')
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses a tenant-restricted caller changing an existing template' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.ConditionalAccess.ReadWrite')
        $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 403
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'checks lower-case types against the real partition' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.ConditionalAccess.ReadWrite')
        $script:CippAllowedTenantsStorage.Value = @('tenant-1')
        (Invoke-Edit 'catemplate').StatusCode | Should -Be 403
    }

    It 'lets an unrestricted caller with the permission save' {
        $script:CallerPermissions = @('CIPP.Core.ReadWrite', 'Tenant.ConditionalAccess.ReadWrite')
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }
}

# A synced template is detached from its library when edited: an Intune one is forked under a new
# GUID, a CA one has its SHA cleared. A template imported once from the catalog is not synced, so it
# is edited in place and keeps the repo link the catalog uses for its badges.
Describe 'Invoke-ExecEditTemplate manual catalog imports' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity { }
        Mock Set-CIPPIntuneTemplate { }
        $script:IntuneJson = '{"Displayname":"x","Type":"Catalog","RAWJson":"{\"name\":\"x\"}"}'
    }
    AfterEach { $script:Row = $null }

    It 'edits a manual Intune import in place and keeps its repo link' {
        $script:Row = [pscustomobject]@{ RowKey = 'template-1'; JSON = $script:IntuneJson; SHA = 'sha-1'; Source = 'Org/repo'; SourcePath = 'IntuneTemplate/x.json'; ManualImport = $true }
        (Invoke-Edit 'IntuneTemplate').StatusCode | Should -Be 200
        Should -Invoke Set-CIPPIntuneTemplate -Times 1 -Exactly -ParameterFilter {
            $GUID -eq 'template-1' -and $Metadata.ManualImport -eq $true -and $Metadata.SHA -eq 'sha-1' -and
            $Metadata.Source -eq 'Org/repo' -and $Metadata.SourcePath -eq 'IntuneTemplate/x.json'
        }
    }

    It 'still forks a synced Intune template under a new GUID' {
        $script:Row = [pscustomobject]@{ RowKey = 'template-1'; JSON = $script:IntuneJson; SHA = 'sha-1'; Source = 'Org/repo' }
        (Invoke-Edit 'IntuneTemplate').StatusCode | Should -Be 200
        Should -Invoke Set-CIPPIntuneTemplate -Times 1 -Exactly -ParameterFilter { $GUID -ne 'template-1' -and $null -eq $Metadata }
    }

    # Deployment reads these references to create the reusable settings the policy points at
    It 'keeps the reusable-setting references of an edited Intune template' {
        $script:Row = [pscustomobject]@{ RowKey = 'template-1'; JSON = '{"Displayname":"x","Type":"Catalog","RAWJson":"{\"name\":\"x\"}","ReusableSettings":[{"GUID":"rs-1","displayName":"Firewall group"}]}' }
        (Invoke-Edit 'IntuneTemplate').StatusCode | Should -Be 200
        Should -Invoke Set-CIPPIntuneTemplate -Times 1 -Exactly -ParameterFilter { @($ReusableSettings).Count -eq 1 -and @($ReusableSettings)[0].GUID -eq 'rs-1' }
    }

    It 'keeps the SHA of a manual CA import' {
        $script:Row = [pscustomobject]@{ RowKey = 'template-1'; SHA = 'sha-1'; ManualImport = $true }
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { -not $Entity.ContainsKey('SHA') }
    }

    It 'still clears the SHA of a synced CA template' {
        $script:Row = [pscustomobject]@{ RowKey = 'template-1'; SHA = 'sha-1' }
        (Invoke-Edit 'CATemplate').StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.ContainsKey('SHA') -and $Entity.SHA -eq '' }
    }
}
