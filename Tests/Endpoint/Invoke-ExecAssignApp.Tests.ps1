# Pester tests for Invoke-ExecAssignApp assignment mode defaults.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAssignApp.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Set-CIPPAssignedApplication { param($ApplicationId, $TenantFilter, $Intent, $APIName, $Headers, $GroupName, $AssignmentMode) }

    . $FunctionPath
}

Describe 'Invoke-ExecAssignApp assignment mode' {
    BeforeEach {
        $script:assignmentMode = $null
        Mock -CommandName Set-CIPPAssignedApplication -MockWith {
            $script:assignmentMode = $AssignmentMode
        }
    }

    It 'defaults omitted assignment mode to append' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignApp' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'app-1'
                AppType      = 'Win32Lob'
                AssignTo     = 'AllDevices'
            }
        }

        $response = Invoke-ExecAssignApp -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:assignmentMode | Should -Be 'append'
    }

    It 'preserves explicit replace mode' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignApp' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{
                tenantFilter   = 'contoso.onmicrosoft.com'
                ID             = 'app-1'
                AppType        = 'Win32Lob'
                AssignTo       = 'AllDevices'
                assignmentMode = 'replace'
            }
        }

        $null = Invoke-ExecAssignApp -Request $request -TriggerMetadata $null

        $script:assignmentMode | Should -Be 'replace'
    }
}
