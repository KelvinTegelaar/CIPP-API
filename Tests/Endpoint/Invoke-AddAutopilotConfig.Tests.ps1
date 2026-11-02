# Pester tests for Invoke-AddAutopilotConfig.
#
# Covers the group-assignment forwarding contract: option objects from the frontend
# picker are normalized to bare ids, bare string ids pass through, group ids reach
# the helper for every selected tenant, and the invalid-name guard short-circuits.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddAutopilotConfig.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddAutopilotConfig.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The endpoint references the unqualified [HttpStatusCode], which only resolves in the
    # Functions host. Register it as a type accelerator so the source parses here too.
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    # Declare the splatted keys so they bind as real parameters (a bare stub would swallow
    # them into $args and Pester's ParameterFilter would see nulls).
    function Set-CIPPDefaultAPDeploymentProfile {
        param(
            $DisplayName, $Description, $UserType, $DeploymentMode, $AssignTo, $GroupIds,
            $DeviceNameTemplate, $AllowWhiteGlove, $CollectHash, $HideChangeAccount,
            $HidePrivacy, $HideTerms, $Autokeyboard, $Language, $Headers, $APIName, $TenantFilter
        )
    }
    function Test-CIPPAutopilotProfileName { }

    . $FunctionPath
}

Describe 'Invoke-AddAutopilotConfig' {
    BeforeEach {
        Mock -CommandName Test-CIPPAutopilotProfileName -MockWith { [PSCustomObject]@{ IsValid = $true; Message = '' } }
        Mock -CommandName Set-CIPPDefaultAPDeploymentProfile -MockWith { 'done' }
    }

    It 'forwards normalized group ids to the helper for every selected tenant' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAutopilotConfig' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                Assignto        = $true
                Description     = 'Test'
                DisplayName     = 'AP Test'
                GroupIds        = @(@{ value = 'group-1'; label = 'Group 1' }, @{ value = 'group-2'; label = 'Group 2' })
                selectedTenants = @(@{ value = 'tenant-a' }, @{ value = 'tenant-b' })
            }
        }

        $response = Invoke-AddAutopilotConfig -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 2 -ParameterFilter {
            $GroupIds -contains 'group-1' -and $GroupIds -contains 'group-2' -and $AssignTo -eq $true
        }
    }

    It 'passes bare string group ids through unchanged' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAutopilotConfig' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                Assignto        = $false
                Description     = 'Test'
                DisplayName     = 'AP Test'
                GroupIds        = @('group-1', '')
                selectedTenants = @(@{ value = 'tenant-a' })
            }
        }

        $response = Invoke-AddAutopilotConfig -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -ParameterFilter {
            $GroupIds.Count -eq 1 -and $GroupIds[0] -eq 'group-1'
        }
    }

    It 'propagates profile or assignment failures from the helper' {
        Mock -CommandName Set-CIPPDefaultAPDeploymentProfile -MockWith { throw 'assignment failed' }
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAutopilotConfig' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                Assignto        = $false
                Description     = 'Test'
                DisplayName     = 'AP Test'
                GroupIds        = @('group-1')
                selectedTenants = @(@{ value = 'tenant-a' })
            }
        }

        { Invoke-AddAutopilotConfig -Request $request -TriggerMetadata $null } |
            Should -Throw 'assignment failed'
    }

    It 'rejects an invalid profile name without calling the helper' {
        Mock -CommandName Test-CIPPAutopilotProfileName -MockWith { [PSCustomObject]@{ IsValid = $false; Message = 'Name rejected' } }
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAutopilotConfig' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{
                Assignto        = $true
                Description     = 'Test'
                DisplayName     = 'Bad-Name'
                selectedTenants = @(@{ value = 'tenant-a' })
            }
        }

        $response = Invoke-AddAutopilotConfig -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Be 'Name rejected'
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 0
    }
}
