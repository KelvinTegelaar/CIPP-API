BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Resolve-CIPPCAPolicyNames.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAUserNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAGroupNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Remove-ODataProperties.ps1')

    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp, $ScheduleRetry)
        $script:GraphWrites.Add(@{ Uri = $uri; Type = $type; Body = $body })
        [pscustomobject]@{ id = 'created-policy-id' }
    }
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $asApp, [switch]$ComplexFilter) throw "Unexpected live Graph GET in test: $uri" }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $asapp) @() }
    function Write-LogMessage {
        [CmdletBinding()] param($API, $tenant, $TenantFilter, $Headers, $message, $sev, $LogData)
        $script:Logs.Add([pscustomobject]@{ Message = $message; Sev = $sev })
    }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTable { [CmdletBinding()] param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($filter) @() }
    function Start-Sleep { [CmdletBinding()] param($Seconds) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCAUnresolvedVariable.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPCAPolicy.ps1')

    $script:InTenant = '00000003-0000-0ff1-ce00-000000000000'
    $script:Missing = '6aa00308-ea33-4caa-90d6-ae905d8cb51b'
    function Invoke-Deploy([string[]]$Include, [string[]]$Exclude) {
        $script:GraphWrites = [System.Collections.Generic.List[object]]::new()
        $script:Logs = [System.Collections.Generic.List[object]]::new()
        $RawJSON = [ordered]@{
            displayName   = 'Require MFA'
            state         = 'disabled'
            conditions    = @{ users = @{ includeUsers = @('All') }; applications = @{ includeApplications = $Include; excludeApplications = $Exclude }; clientAppTypes = @('all') }
            grantControls = @{ operator = 'OR'; builtInControls = @('mfa') }
        } | ConvertTo-Json -Depth 10
        $null = New-CIPPCAPolicy -RawJSON $RawJSON -TenantFilter 'contoso.com' -State 'disabled' -Overwrite $true -PreloadedCAPolicies @([pscustomobject]@{ id = 'other'; displayName = 'Unrelated' }) -PreloadedServicePrincipals @([pscustomobject]@{ appId = $script:InTenant })
        $script:GraphWrites.Where({ $_.Uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' })[-1].Body | ConvertFrom-Json
    }
}

Describe 'New-CIPPCAPolicy app filtering' {
    It 'drops an excluded app that is not in the tenant and logs a warning naming it' {
        $Body = Invoke-Deploy -Include @('All') -Exclude @($script:InTenant, $script:Missing, 'Office365')
        @($Body.conditions.applications.excludeApplications) | Should -Be @($script:InTenant, 'Office365')
        $Warning = @($script:Logs.Where({ $_.Sev -eq 'Warning' }))
        $Warning.Count | Should -Be 1
        $Warning[0].Message | Should -BeLike "*'Require MFA' excludes apps that are not in this tenant ($script:Missing)*"
    }

    It 'logs no warning when every excluded app is in the tenant' {
        $null = Invoke-Deploy -Include @('All') -Exclude @($script:InTenant)
        $script:Logs.Where({ $_.Sev -eq 'Warning' }).Count | Should -Be 0
    }

    It 'drops an included app that is not in the tenant and logs a warning naming it' {
        $Body = Invoke-Deploy -Include @($script:InTenant, $script:Missing) -Exclude @()
        @($Body.conditions.applications.includeApplications) | Should -Be @($script:InTenant)
        $script:Logs.Where({ $_.Sev -eq 'Warning' -and $_.Message -like "*targets apps that are not in this tenant ($script:Missing)*" }).Count | Should -Be 1
    }

    It 'still refuses a policy whose included apps are all missing' {
        { Invoke-Deploy -Include @($script:Missing) -Exclude @() } | Should -Throw '*None of the applications included*'
    }
}
