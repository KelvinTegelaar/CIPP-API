# Pester tests for how Set-CIPPAssignedApplication picks its include target.
#
# The deploy drawers send a picked group's display name as GroupName next to its id in GroupIds.
# The name switch (AllUsers / AllDevices / AllDevicesAndUsers) must not see that name: a group that
# happens to be called 'AllDevices' has to resolve to the group, never to a tenant-wide target.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPAssignedApplication.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:SalesId = '11111111-1111-1111-1111-111111111111'
}

Describe 'Set-CIPPAssignedApplication include target' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = 'Graph said no' } }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith {
            @([PSCustomObject]@{ id = $script:SalesId; displayName = 'Sales Users' })
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/assignments' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { @{} }
        # The function sleeps a second before posting; not worth paying for in a unit test.
        Mock -CommandName Start-Sleep -MockWith { }
    }

    Context 'a broad target by name' {
        It 'sends the All Devices target' {
            $null = Set-CIPPAssignedApplication -GroupName 'AllDevices' -ApplicationId 'app-1' -Intent 'Required' -TenantFilter $script:Tenant -AssignmentMode 'replace'

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).mobileAppAssignments.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget'
            }
        }
    }

    Context 'a picked group whose display name is a broad-target token' {
        It 'assigns the group by id instead of expanding the name to All Devices' {
            $null = Set-CIPPAssignedApplication -GroupName 'AllDevices' -GroupIds @($script:SalesId) -ApplicationId 'app-1' -Intent 'Required' -TenantFilter $script:Tenant -AssignmentMode 'replace'

            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Targets = ($body | ConvertFrom-Json).mobileAppAssignments.target
                @($Targets).Count -eq 1 -and
                $Targets[0].'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and
                $Targets[0].groupId -eq $script:SalesId
            }
        }
    }
}
