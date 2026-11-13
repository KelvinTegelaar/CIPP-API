# Role templates and group mappings apply to every customer, so a tenant-restricted caller cannot change them,
# and no path may map a reserved partner group (AdminAgents and the like) to a GDAP role.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CippBulkStatusCode { param($Total, $Failed) 200 }
    function Get-CIPPPartnerTenantList { }
    function Get-CIPPHostname { param($Headers, [switch]$PreferCustomDomain) 'cipp.example' }
    function Test-CippTenantInScope { param($Tenant) $script:Unrestricted }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) @([pscustomobject]@{ RowKey = 'T1'; RoleMappings = '[]' }) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Writes.Add('table') }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Writes.Add('remove') }
    function Add-CIPPGDAPRoleTemplate { param($Headers, $TemplateId, $RoleMappings, [switch]$Overwrite) $script:Writes.Add('template') }
    function New-CIPPGDAPRoleMapping { param($Roles, $CustomSuffix, $PartnerTenantId) $script:Writes.Add('groups'); [pscustomobject]@{ Results = @(); RoleMappings = @() } }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp)
        if ($uri -match 'roleDefinitions') { return @([pscustomobject]@{ id = $script:GR }) }
        if ($uri -match 'delegatedAdminRelationships/') { return [pscustomobject]@{ status = 'created' } }
        $script:PartnerGroups
    }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $NoAuthCheck, $AddedHeaders, [switch]$verbose) $script:Writes.Add('graph'); [pscustomobject]@{ id = 'rel'; action = 'lockForApproval' } }

    $ReservedHelper = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPGDAPReservedGroupName.ps1'
    if (Test-Path $ReservedHelper) { . $ReservedHelper }
    foreach ($Name in 'Invoke-ExecGDAPRoleTemplate', 'Invoke-ExecAddGDAPRole', 'Invoke-ExecGDAPInvite') {
        $Path = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter "$Name.ps1").FullName
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Path -Raw)))
    }

    $script:GR = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
    $script:Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@example.com"}'))
    function New-Request($Query, $Body) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'test' }; Headers = @{ 'x-ms-client-principal' = $script:Principal }; Query = $Query; Body = $Body }
    }
    $script:Mapping = [pscustomobject]@{ RoleName = 'Global Reader'; GroupName = 'M365 GDAP Global Reader'; GroupId = 'g-reader'; roleDefinitionId = $script:GR }
}

Describe 'GDAP partner-level configuration writes' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[string]]::new()
        $script:Unrestricted = $true
        $script:PartnerGroups = @(
            [pscustomobject]@{ id = 'g-reader'; displayName = 'M365 GDAP Global Reader' }
            [pscustomobject]@{ id = 'g-aa'; displayName = 'AdminAgents' }
        )
    }

    Context 'tenant-restricted caller' {
        BeforeEach { $script:Unrestricted = $false }

        It 'refuses role template action <_>' -ForEach @('Add', 'Save', 'Edit', 'Delete') {
            $Response = Invoke-ExecGDAPRoleTemplate -Request (New-Request @{ Action = $_ } ([pscustomobject]@{ TemplateId = 'T1'; RoleMappings = @($script:Mapping) })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 403
            $script:Writes | Should -HaveCount 0
        }

        It 'can still list role templates' {
            $Response = Invoke-ExecGDAPRoleTemplate -Request (New-Request @{} $null) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
        }

        It 'refuses group mapping action <_>' -ForEach @('AddRoleAdvanced', 'AddRoleSimple') {
            $Body = [pscustomobject]@{ Action = $_; mappings = @([pscustomobject]@{ GroupId = 'g-reader'; RoleName = 'Global Reader'; roleDefinitionId = $script:GR }) }
            $Response = Invoke-ExecAddGDAPRole -Request (New-Request @{} $Body) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 403
            $script:Writes | Should -HaveCount 0
        }

        It 'can still list partner groups' {
            $Response = Invoke-ExecAddGDAPRole -Request (New-Request @{ Action = 'ListGroups' } $null) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
        }
    }

    Context 'unrestricted caller' {
        It 'saves a role template' {
            $Response = Invoke-ExecGDAPRoleTemplate -Request (New-Request @{ Action = 'Save' } ([pscustomobject]@{ TemplateId = 'T1'; RoleMappings = @($script:Mapping) })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            $script:Writes | Should -Contain 'template'
        }

        It 'hides reserved groups from the group list' {
            $Response = Invoke-ExecAddGDAPRole -Request (New-Request @{ Action = 'ListGroups' } $null) -TriggerMetadata $null
            @($Response.Body.Results.id) | Should -Be @('g-reader')
        }

        It 'refuses an advanced mapping of a reserved group' {
            $Body = [pscustomobject]@{ Action = 'AddRoleAdvanced'; mappings = @([pscustomobject]@{ GroupId = 'g-aa'; RoleName = 'Global Reader'; roleDefinitionId = $script:GR }) }
            $Response = Invoke-ExecAddGDAPRole -Request (New-Request @{} $Body) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 400
            $script:Writes | Should -HaveCount 0
        }

        It 'creates an invite for a template of CIPP groups' {
            $Response = Invoke-ExecGDAPInvite -Request (New-Request @{} ([pscustomobject]@{ Action = 'Create'; roleMappings = @($script:Mapping) })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            $script:Writes | Should -Contain 'graph'
        }

        It 'refuses an invite that maps a reserved group' {
            $Reserved = [pscustomobject]@{ RoleName = 'Global Reader'; GroupName = 'M365 GDAP Global Reader'; GroupId = 'g-aa'; roleDefinitionId = $script:GR }
            $Response = Invoke-ExecGDAPInvite -Request (New-Request @{} ([pscustomobject]@{ Action = 'Create'; roleMappings = @($script:Mapping, $Reserved) })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 400
            $script:Writes | Should -HaveCount 0
        }
    }
}
