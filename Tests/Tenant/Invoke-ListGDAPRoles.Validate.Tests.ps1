# The ?validate=true annotation is opt-in: other consumers of ListGDAPRoles read the plain
# four-property shape, and a Graph failure must degrade to Unknown rather than break the list.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GDAP/Invoke-ListGDAPRoles.ps1'

    # The Functions worker exposes [HttpStatusCode] as an accelerator; register it for tests.
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $AsApp) }
    function Test-CIPPGDAPGroupMappings { param($RoleMappings, $PartnerGroups, $APIName, $Headers) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    function New-Request {
        param($Validate)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListGDAPRoles' }
            Headers = @{}
            Query   = @{ validate = $Validate }
        }
    }
}

Describe 'Invoke-ListGDAPRoles' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [PSCustomObject]@{
                    GroupName        = 'M365 GDAP User Administrator'
                    GroupId          = 'group-user-admin'
                    RoleName         = 'User Administrator'
                    roleDefinitionId = 'role-user-admin'
                }
                [PSCustomObject]@{
                    GroupName        = 'M365 GDAP Intune Administrator'
                    GroupId          = 'group-intune'
                    RoleName         = 'Intune Administrator'
                    roleDefinitionId = 'role-intune'
                }
            )
        }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Test-CIPPGDAPGroupMappings -MockWith {
            [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{ RoleName = 'User Administrator'; GroupName = 'M365 GDAP User Administrator'; GroupId = 'group-user-admin'; Status = 'Valid'; Message = ''; OldGroupId = $null }
                    [PSCustomObject]@{ RoleName = 'Intune Administrator'; GroupName = 'M365 GDAP Intune Administrator'; GroupId = 'group-intune-new'; Status = 'Stale'; Message = 'stale id'; OldGroupId = 'group-intune' }
                )
            }
        }
    }

    It 'returns the plain mapping shape without the flag' {
        $Response = Invoke-ListGDAPRoles -Request (New-Request) -TriggerMetadata $null

        Should -Invoke Test-CIPPGDAPGroupMappings -Times 0
        Should -Invoke New-GraphGetRequest -Times 0
        $Response.Body.Count | Should -Be 2
        $Response.Body[0].PSObject.Properties.Name | Should -Be @('GroupName', 'GroupId', 'RoleName', 'roleDefinitionId')
    }

    It 'annotates each mapping with its group status when asked' {
        $Response = Invoke-ListGDAPRoles -Request (New-Request -Validate $true) -TriggerMetadata $null

        Should -Invoke Test-CIPPGDAPGroupMappings -Times 1
        $Valid = $Response.Body | Where-Object -Property GroupId -EQ 'group-user-admin'
        $Valid.GroupStatus | Should -Be 'Valid'
        # A stale result carries the original id as OldGroupId, so it still lands on its own row.
        $Stale = $Response.Body | Where-Object -Property GroupId -EQ 'group-intune'
        $Stale.GroupStatus | Should -Be 'Stale'
        $Stale.GroupStatusMessage | Should -Be 'stale id'
    }

    It 'degrades to Unknown when the group check fails' {
        Mock -CommandName Test-CIPPGDAPGroupMappings -MockWith { throw 'graph is down' }

        $Response = Invoke-ListGDAPRoles -Request (New-Request -Validate $true) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.GroupStatus | Should -Be @('Unknown', 'Unknown')
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' }
    }
}
