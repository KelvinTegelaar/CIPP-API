# Repair must recreate groups that no longer exist, not just report them: the UI promises
# "Recreate ... as a new, empty security group", and a group created by the registry pass must be
# visible to the template pass so shared mappings re-link instead of creating a duplicate.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GDAP/Invoke-ExecGDAPRepairRoleMappings.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp) }
    function Test-CIPPGDAPGroupMappings { param($RoleMappings, $PartnerGroups, [switch]$CreateMissing, [switch]$WriteBack, $TemplateId, $APIName, $Headers) }
    function Test-CIPPGDAPRelationships { param($Headers) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    $script:Request = [pscustomobject]@{
        Params  = @{ CIPPEndpoint = 'ExecGDAPRepairRoleMappings' }
        Headers = @{}
    }
}

Describe 'Invoke-ExecGDAPRepairRoleMappings' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Context -eq 'GDAPRoles') {
                @([PSCustomObject]@{ RoleName = 'Helpdesk Administrator'; GroupName = 'M365 GDAP Helpdesk Administrator'; GroupId = 'gone'; roleDefinitionId = 'role-helpdesk' })
            } else {
                @([PSCustomObject]@{ RowKey = 'Template A'; RoleMappings = '[{"RoleName":"Helpdesk Administrator","GroupName":"M365 GDAP Helpdesk Administrator","GroupId":"gone","roleDefinitionId":"role-helpdesk"}]' })
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith { @([PSCustomObject]@{ id = 'existing-1'; displayName = 'M365 GDAP Global Reader' }) }
        Mock -CommandName Test-CIPPGDAPRelationships -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Test-CIPPGDAPGroupMappings -MockWith {
            $script:Calls.Add(@{ CreateMissing = [bool]$CreateMissing; PartnerGroupIds = @($PartnerGroups.id); TemplateId = $TemplateId })
            $Status = if ($PartnerGroups.displayName -contains 'M365 GDAP Helpdesk Administrator') { 'Stale' } elseif ($CreateMissing) { 'Created' } else { 'Missing' }
            [PSCustomObject]@{
                Results       = @([PSCustomObject]@{ RoleName = 'Helpdesk Administrator'; GroupName = 'M365 GDAP Helpdesk Administrator'; GroupId = 'new-1'; Status = $Status; Message = "status $Status"; OldGroupId = 'gone' })
                RoleMappings  = @()
                Valid         = ($Status -ne 'Missing')
                MissingGroups = @()
            }
        }
    }

    It 'asks the validator to recreate missing groups on both passes' {
        $null = Invoke-ExecGDAPRepairRoleMappings -Request $script:Request -TriggerMetadata $null

        $script:Calls.Count | Should -Be 2
        $script:Calls[0].CreateMissing | Should -BeTrue
        $script:Calls[1].CreateMissing | Should -BeTrue
    }

    It 'reports a recreated group as success' {
        $Response = Invoke-ExecGDAPRepairRoleMappings -Request $script:Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results | Where-Object { $_.state -eq 'error' }).Count | Should -Be 0
        $Response.Body.Results[0].resultText | Should -Match 'status Created'
    }

    It 'feeds groups created by the registry pass into the template pass' {
        $Response = Invoke-ExecGDAPRepairRoleMappings -Request $script:Request -TriggerMetadata $null

        $script:Calls[1].PartnerGroupIds | Should -Contain 'new-1'
        $Response.Body.Results[1].resultText | Should -Match 'status Stale'
    }
}
