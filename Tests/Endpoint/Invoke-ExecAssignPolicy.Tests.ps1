# Pester tests for Invoke-ExecAssignPolicy assignment mode defaults.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAssignPolicy.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Set-CIPPAssignedPolicy { param($PolicyId, $TenantFilter, $GroupName, $Type, $Headers, $AssignmentMode) }

    . $FunctionPath
}

Describe 'Invoke-ExecAssignPolicy assignment mode' {
    BeforeEach {
        $script:assignmentMode = $null
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith {
            $script:assignmentMode = $AssignmentMode
        }
    }

    It 'defaults omitted assignment mode to append' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignPolicy' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'policy-1'
                Type         = 'configurationPolicies'
                AssignTo     = 'AllDevices'
            }
        }

        $response = Invoke-ExecAssignPolicy -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:assignmentMode | Should -Be 'append'
    }

    It 'preserves explicit replace mode' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignPolicy' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter  = 'contoso.onmicrosoft.com'
                ID            = 'policy-1'
                Type          = 'configurationPolicies'
                AssignTo      = 'AllDevices'
                assignmentMode = 'replace'
            }
        }

        $null = Invoke-ExecAssignPolicy -Request $request -TriggerMetadata $null

        $script:assignmentMode | Should -Be 'replace'
    }
}
