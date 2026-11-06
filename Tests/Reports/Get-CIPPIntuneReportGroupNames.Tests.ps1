# The cached Intune reports name assignment groups from the shared IntunePolicyGroups snapshot, and fall back
# to the Groups cache only for a tenant that has no snapshot.

BeforeDiscovery {
    $Assignments = @(
        [pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }
        [pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g2' } }
    )
    $Cases = @(
        @{ Report = 'Get-CIPPIntuneCompliancePolicyReport'; Type = 'IntuneDeviceCompliancePolicies'; Include = 'PolicyAssignment'; Exclude = 'PolicyExclude'
            Policy = [pscustomobject]@{ id = 'p1'; displayName = 'Policy'; '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; assignments = $Assignments } }
        @{ Report = 'Get-CIPPIntuneAppProtectionPolicyReport'; Type = 'IntuneAppProtectionManagedAppPolicies'; Include = 'PolicyAssignment'; Exclude = 'PolicyExclude'
            Policy = [pscustomobject]@{ id = 'p1'; displayName = 'Policy'; URLName = 'iosManagedAppProtection'; assignments = $Assignments } }
        @{ Report = 'Get-CIPPIntuneScriptReport'; Type = 'IntuneWindowsScripts'; Include = 'ScriptAssignment'; Exclude = 'ScriptExclude'
            Policy = [pscustomobject]@{ id = 'p1'; displayName = 'Script'; assignments = $Assignments } }
        @{ Report = 'Get-CIPPIntuneApplicationReport'; Type = 'IntuneApplications'; Include = 'AppAssignment'; Exclude = 'AppExclude'
            Policy = [pscustomobject]@{ id = 'p1'; displayName = 'App'; assignments = $Assignments } }
    )
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type) $script:Rows[$Type] }
    foreach ($Report in 'Get-CIPPIntuneCompliancePolicyReport', 'Get-CIPPIntuneAppProtectionPolicyReport', 'Get-CIPPIntuneScriptReport', 'Get-CIPPIntuneApplicationReport') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Report.ps1")
    }

    function New-Row([string]$Type, $Data) {
        [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = "$Type-$($Data.id)"; Timestamp = [DateTimeOffset]::UtcNow; Data = ($Data | ConvertTo-Json -Depth 10 -Compress) }
    }
}

Describe 'Cached Intune report group names' {
    BeforeEach {
        $script:Rows = @{
            IntunePolicyGroups = @((New-Row 'IntunePolicyGroups' @{ id = 'g1'; displayName = 'Snapshot One' }), (New-Row 'IntunePolicyGroups' @{ id = 'g2'; displayName = 'Snapshot Two' }))
            Groups             = @((New-Row 'Groups' @{ id = 'g1'; displayName = 'Directory One' }), (New-Row 'Groups' @{ id = 'g2'; displayName = 'Directory Two' }))
        }
    }

    It '<Report> names groups from the IntunePolicyGroups snapshot' -ForEach $Cases {
        $script:Rows[$Type] = @(New-Row $Type $Policy)
        $Result = @(& $Report -TenantFilter 'contoso.com')
        $Result[0].$Include | Should -Be 'Snapshot One'
        $Result[0].$Exclude | Should -Be 'Snapshot Two'
    }

    It '<Report> falls back to the Groups cache without a snapshot' -ForEach $Cases {
        $script:Rows[$Type] = @(New-Row $Type $Policy)
        $script:Rows.Remove('IntunePolicyGroups')
        $Result = @(& $Report -TenantFilter 'contoso.com')
        $Result[0].$Include | Should -Be 'Directory One'
        $Result[0].$Exclude | Should -Be 'Directory Two'
    }
}
