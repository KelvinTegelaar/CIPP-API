# Pester tests for Invoke-ListAdministrativeUnitUsage.
# Entra role assignments are kept only when scoped to the unit, and keep the Roles page row shape so its
# actions work on them. Exchange assignments scoped to the unit are added, apps named from Exchange's
# service principals. Exchange is best effort: a failed read returns the Entra rows with 207.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/AdministrativeUnits/Invoke-ListAdministrativeUnitUsage.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPPIMRoleAssignments { param($TenantFilter) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }
    function Test-IsGuid { param([Parameter(Mandatory)][string]$String) [guid]::TryParse($String, [ref][guid]::Empty) }

    . $FunctionPath

    $script:UnitId = '11111111-1111-1111-1111-111111111111'
    function New-UsageRequest {
        param([hashtable]$Query = @{})
        $RequestQuery = @{ tenantFilter = 'contoso.com'; ID = $script:UnitId; displayName = 'Sales' }
        foreach ($Key in $Query.Keys) { $RequestQuery[$Key] = $Query[$Key] }
        [pscustomobject]@{ Query = [pscustomobject]$RequestQuery; Body = $null; Headers = @{}; Params = @{ CIPPEndpoint = 'ListAdministrativeUnitUsage' } }
    }
}

Describe 'Invoke-ListAdministrativeUnitUsage' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Get-CIPPPIMRoleAssignments {
            [pscustomobject]@{ PrincipalId = 'user-1'; RoleDisplayName = 'Helpdesk Administrator'; DirectoryScopeId = "/administrativeUnits/$($script:UnitId)"; AssignmentType = 'Eligible'; PIMCapable = $true }
            [pscustomobject]@{ PrincipalId = 'user-2'; RoleDisplayName = 'User Administrator'; DirectoryScopeId = '/'; AssignmentType = 'Permanent'; PIMCapable = $true }
            [pscustomobject]@{ PrincipalId = 'user-3'; RoleDisplayName = 'User Administrator'; DirectoryScopeId = '/administrativeUnits/99999999-9999-9999-9999-999999999999'; AssignmentType = 'Active'; PIMCapable = $true }
        }
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-ManagementRoleAssignment' {
                    [pscustomobject]@{ Guid = 'ra-1'; Role = 'Application Mail.Read'; RoleAssignee = 'sp-exo-1'; RecipientAdministrativeUnitScope = $script:UnitId; Enabled = $true }
                    [pscustomobject]@{ Guid = 'ra-2'; Role = 'Mail Recipients'; RoleAssigneeName = 'Helpdesk'; RoleAssigneeType = 'RoleGroup'; RecipientAdministrativeUnitScope = 'Sales'; Enabled = $true }
                    [pscustomobject]@{ Guid = 'ra-3'; Role = 'Application Mail.Send'; RoleAssignee = 'sp-exo-1'; Enabled = $true }
                }
                'Get-ServicePrincipal' { [pscustomobject]@{ Identity = 'sp-exo-1'; AppId = 'app-1'; ObjectId = 'sp-1'; DisplayName = 'Mail Sync' } }
            }
        }
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'all tenants'; Query = @{ tenantFilter = 'AllTenants' } }
        @{ Case = 'an id that is not a GUID'; Query = @{ ID = 'Sales' } }
    ) {
        (Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest -Query $Query)).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPPIMRoleAssignments -Times 0
    }

    It 'keeps only the role assignments scoped to the unit, in the Roles page shape' {
        $Rows = @((Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest)).Body)
        $Entra = @($Rows | Where-Object Source -EQ 'Entra role')

        $Entra.PrincipalId | Should -Be @('user-1')
        $Entra[0].AssignmentType | Should -BeExactly 'Eligible'
        $Entra[0].PIMCapable | Should -BeTrue
    }

    It 'adds the Exchange assignments scoped to the unit by id or name, naming the app' {
        $Response = Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest)
        $Exchange = @($Response.Body | Where-Object Source -Like 'Exchange*')

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Exchange.Id | Should -Be @('ra-1', 'ra-2')
        $Exchange[0].Source | Should -BeExactly 'Exchange app role'
        $Exchange[0].PrincipalDisplayName | Should -BeExactly 'Mail Sync'
        $Exchange[0].ServicePrincipalId | Should -BeExactly 'sp-1'
        $Exchange[1].Source | Should -BeExactly 'Exchange admin role'
        $Exchange[1].PrincipalDisplayName | Should -BeExactly 'Helpdesk'
    }

    It 'does not read Exchange service principals when no app role is scoped to the unit' {
        Mock New-ExoRequest { if ($cmdlet -eq 'Get-ManagementRoleAssignment') { [pscustomobject]@{ Guid = 'ra-2'; Role = 'Mail Recipients'; RecipientAdministrativeUnitScope = $script:UnitId } } }

        $null = Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest)

        Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Get-ServicePrincipal' }
    }

    It 'returns the Entra rows with 207 when Exchange cannot be read' {
        Mock New-ExoRequest { throw 'Exchange unavailable' }

        $Response = Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
        @($Response.Body).Count | Should -Be 1
    }

    It 'returns 500 when the role assignments cannot be read' {
        Mock Get-CIPPPIMRoleAssignments { throw 'Graph unavailable' }

        $Response = Invoke-ListAdministrativeUnitUsage -Request (New-UsageRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -BeLike 'Failed to read the role assignments scoped to administrative unit*'
    }
}
