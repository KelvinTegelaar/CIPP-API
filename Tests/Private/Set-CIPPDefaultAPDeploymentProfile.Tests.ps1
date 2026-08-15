# Pester tests for Set-CIPPDefaultAPDeploymentProfile.
#
# Covers the assignment half of profile creation: the all-devices branch, the new
# group-target branch (one assignment per group, already-assigned groups skipped),
# no assignment when neither is requested, the invalid-name guard, and the error path.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPDefaultAPDeploymentProfile.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPDefaultAPDeploymentProfile.ps1 under Modules/' }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = [string]$Exception } }
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type) }
    function Test-CIPPAutopilotProfileName { [CmdletBinding()] param($DisplayName) [PSCustomObject]@{ IsValid = $true; Message = '' } }
    function Write-LogMessage { [CmdletBinding()] param($Headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Set-CIPPDefaultAPDeploymentProfile assignment handling' {
    BeforeEach {
        $script:PostCalls = @()

        Mock -CommandName Test-CIPPAutopilotProfileName -MockWith { [PSCustomObject]@{ IsValid = $true; Message = '' } }
        Mock -CommandName New-GraphGETRequest -ParameterFilter { $uri -like '*windowsAutopilotDeploymentProfiles' -and $uri -notlike '*assignments*' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*windowsAutopilotDeploymentProfiles' -and $uri -notlike '*assignments*' } -MockWith {
            $script:PostCalls += @{ uri = $uri; body = $body; type = $type }
            [PSCustomObject]@{ id = 'profile-1' }
        }
        Mock -CommandName New-GraphGETRequest -ParameterFilter { $uri -like '*assignments*' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*assignments*' } -MockWith {
            $script:PostCalls += @{ uri = $uri; body = $body; type = $type }
            [PSCustomObject]@{ id = 'assignment-1' }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = 'boom' } }
    }

    It 'creates one groupAssignmentTarget assignment per group' {
        Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
            -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $false -GroupIds @('group-1', 'group-2') `
            -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false

        $AssignmentCalls = @($script:PostCalls | Where-Object { $_.uri -like '*assignments' })
        $AssignmentCalls.Count | Should -Be 2
        $AssignmentCalls[0].body | Should -BeLike '*#microsoft.graph.groupAssignmentTarget*'
        $AssignmentCalls[0].body | Should -BeLike '*group-1*'
        $AssignmentCalls[1].body | Should -BeLike '*group-2*'
        $AssignmentCalls | ForEach-Object { $_.body | Should -Not -BeLike '*allDevicesAssignmentTarget*' }
    }

    It 'skips groups that already have an assignment' {
        Mock -CommandName New-GraphGETRequest -ParameterFilter { $uri -like '*assignments*' } -MockWith {
            @(
                [PSCustomObject]@{ target = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'group-1' } }
            )
        }

        Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
            -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $false -GroupIds @('group-1', 'group-2') `
            -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false

        $AssignmentCalls = @($script:PostCalls | Where-Object { $_.uri -like '*assignments' })
        $AssignmentCalls.Count | Should -Be 1
        $AssignmentCalls[0].body | Should -BeLike '*group-2*'
    }

    It 'throws when existing group assignments cannot be read' {
        Mock -CommandName New-GraphGETRequest -ParameterFilter { $uri -like '*assignments*' } -MockWith { throw 'assignment lookup failed' }

        { Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
                -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $false -GroupIds @('group-1') `
                -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false } |
            Should -Throw '*Failed*'

        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $uri -like '*assignments*' } -Times 0
    }

    It 'throws when any group assignment post fails' {
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*assignments*' } -MockWith { throw 'assignment post failed' }

        { Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
                -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $false -GroupIds @('group-1') `
                -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false } |
            Should -Throw '*Failed*'
    }

    It 'keeps the all-devices branch when AssignTo is true, ignoring GroupIds' {
        Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
            -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $true -GroupIds @('group-1') `
            -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false

        $AssignmentCalls = @($script:PostCalls | Where-Object { $_.uri -like '*assignments' })
        $AssignmentCalls.Count | Should -Be 1
        $AssignmentCalls[0].body | Should -BeLike '*allDevicesAssignmentTarget*'
    }

    It 'creates no assignment when neither all devices nor groups are requested' {
        Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -Description '' `
            -DeploymentMode 'singleUser' -UserType 'standard' -AssignTo $false -GroupIds @() `
            -HidePrivacy $true -HideTerms $true -AutoKeyboard $true -AllowWhiteGlove $true -CollectHash $false

        @($script:PostCalls | Where-Object { $_.uri -like '*assignments' }).Count | Should -Be 0
    }

    It 'refuses an invalid profile name without calling Graph' {
        Mock -CommandName Test-CIPPAutopilotProfileName -MockWith { [PSCustomObject]@{ IsValid = $false; Message = 'Name rejected' } }

        { Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'Bad-Name' -AssignTo $false -GroupIds @('group-1') } |
            Should -Throw 'Name rejected'
        @($script:PostCalls).Count | Should -Be 0
        Should -Invoke Write-LogMessage -ParameterFilter { $message -eq 'Name rejected' }
    }

    It 'throws a readable error when the profile lookup fails' {
        Mock -CommandName New-GraphGETRequest -ParameterFilter { $uri -like '*windowsAutopilotDeploymentProfiles' -and $uri -notlike '*assignments*' } -MockWith { throw 'graph down' }

        { Set-CIPPDefaultAPDeploymentProfile -TenantFilter $script:Tenant -DisplayName 'AP Test' -AssignTo $true } |
            Should -Throw '*Failed*'
        Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' }
    }
}
