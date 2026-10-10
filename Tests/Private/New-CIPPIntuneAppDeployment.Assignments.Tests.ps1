# Pester tests for how New-CIPPIntuneAppDeployment forwards group targets to
# Set-CIPPAssignedApplication.
#
# The Application Deployment drawer queues assignTo/excludeGroup as display names. When a single
# tenant is selected it picks groups by id instead and queues GroupIds/ExcludeGroupIds alongside
# the names; those ids must reach Set-CIPPAssignedApplication, which prefers them over name
# resolution. Callers that queue names only (templates, standards, baselines) must see no new
# parameters at all, so their name-based resolution is untouched.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param([string]$TenantFilter, $Text, [switch]$EscapeForJson) }
    function Get-CIPPMSPAppInstallCommand { [CmdletBinding()] param($RmmName, $Params, $Tenant, $PackageName) }
    function Add-CIPPWinGetApp { [CmdletBinding()] param($AppBody, $TenantFilter) }
    function Add-CIPPPackagedApplication { [CmdletBinding()] param($TenantFilter, $Intunexml, $Infile, $EncryptionInfo, $DisplayName, $IntuneBody) }
    function Add-CIPPW32ScriptApplication { [CmdletBinding()] param($TenantFilter, $Properties) }
    function Get-CIPPOfficeAppBody { [CmdletBinding()] param($Config) }
    function Get-CIPPEdgeAppBody { [CmdletBinding()] param($Config) }
    function Set-CIPPAssignedApplication { [CmdletBinding()] param($GroupName, $ExcludeGroup, $ExcludeGroupIds, $ExcludeGroupNames, $Intent, $AppType, $ApplicationId, $TenantFilter, $GroupIds, $AssignmentMode, $AssignmentDirection, $APIName, $Headers, $AssignmentFilterName, $AssignmentFilterType) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPIntuneAppDeployment.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # A queued Store (WinGet) app: IntuneBody is pre-built by Invoke-AddStoreApp, so the function
    # only has to create it and assign it.
    function New-QueuedStoreApp {
        param([hashtable]$Extra = @{})
        $Config = [ordered]@{
            tenant          = $script:Tenant
            Applicationname = 'Contoso Viewer'
            assignTo        = 'Sales, Marketing'
            excludeGroup    = 'Interns'
            type            = 'WinGet'
            IntuneBody      = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.winGetApp'; displayName = 'Contoso Viewer' }
        }
        foreach ($Key in $Extra.Keys) { $Config[$Key] = $Extra[$Key] }
        # Round-trip through JSON the way the apps table does, so arrays arrive as they would at run time.
        return ([pscustomobject]$Config | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
    }
}

Describe 'New-CIPPIntuneAppDeployment group id forwarding' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        # No app with this name exists yet, so the create path is taken.
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName Add-CIPPWinGetApp -MockWith { [pscustomobject]@{ Id = 'app-0001' } }
        Mock -CommandName Set-CIPPAssignedApplication -MockWith { }
    }

    Context 'a queue entry from the single-tenant picker (ids next to the names)' {
        It 'passes GroupIds and ExcludeGroupIds through, keeping the names as GroupName/ExcludeGroup' {
            $AppConfig = New-QueuedStoreApp -Extra @{
                GroupIds        = @('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
                ExcludeGroupIds = @('33333333-3333-3333-3333-333333333333')
            }

            $null = New-CIPPIntuneAppDeployment -AppConfig $AppConfig -TenantFilter $script:Tenant

            Should -Invoke Set-CIPPAssignedApplication -Times 1 -Exactly -ParameterFilter {
                $ApplicationId -eq 'app-0001' -and
                $GroupName -eq 'Sales, Marketing' -and
                $ExcludeGroup -eq 'Interns' -and
                @($GroupIds).Count -eq 2 -and
                $GroupIds[0] -eq '11111111-1111-1111-1111-111111111111' -and
                @($ExcludeGroupIds).Count -eq 1 -and
                $ExcludeGroupIds[0] -eq '33333333-3333-3333-3333-333333333333'
            }
        }
    }

    Context 'a queue entry with names only (multi-tenant deploy, templates, standards)' {
        It 'does not bind GroupIds or ExcludeGroupIds at all, so name resolution is untouched' {
            $AppConfig = New-QueuedStoreApp

            $null = New-CIPPIntuneAppDeployment -AppConfig $AppConfig -TenantFilter $script:Tenant

            Should -Invoke Set-CIPPAssignedApplication -Times 1 -Exactly -ParameterFilter {
                $GroupName -eq 'Sales, Marketing' -and
                $ExcludeGroup -eq 'Interns' -and
                $null -eq $GroupIds -and
                $null -eq $ExcludeGroupIds
            }
        }
    }

    Context 'a queue entry with empty id arrays (picker shown but nothing picked)' {
        It 'treats empty arrays as absent' {
            $AppConfig = New-QueuedStoreApp -Extra @{ GroupIds = @(); ExcludeGroupIds = @() }

            $null = New-CIPPIntuneAppDeployment -AppConfig $AppConfig -TenantFilter $script:Tenant

            Should -Invoke Set-CIPPAssignedApplication -Times 1 -Exactly -ParameterFilter {
                $null -eq $GroupIds -and
                $null -eq $ExcludeGroupIds
            }
        }
    }
}
