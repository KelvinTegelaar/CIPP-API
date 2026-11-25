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

    function Set-CIPPAssignedPolicy { param($PolicyId, $TenantFilter, $GroupName, $GroupNames, $GroupIds, $Type, $Headers, $AssignmentMode) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

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

Describe 'Invoke-ExecAssignPolicy group names' {
    BeforeAll {
        function New-NamesRequest($Names) {
            [pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecAssignPolicy' }
                Headers = @{}
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; ID = 'policy-1'; Type = 'configurationPolicies'; GroupNames = $Names }
            }
        }
    }
    BeforeEach {
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { 'Assigned' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'g-sales'; displayName = 'Sales' }
                [pscustomobject]@{ id = 'g-finance'; displayName = 'Finance' }
                [pscustomobject]@{ id = 'g-alldevices'; displayName = 'AllDevices' }
                [pscustomobject]@{ id = 'g-dup1'; displayName = 'Twice' }
                [pscustomobject]@{ id = 'g-dup2'; displayName = 'Twice' }
            )
        }
    }

    It 'resolves GroupNames alone to group ids' {
        $response = Invoke-ExecAssignPolicy -Request (New-NamesRequest @('Sales', 'Finance')) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter { (@($GroupIds) -join ',') -eq 'g-sales,g-finance' -and -not $GroupName }
    }

    It 'assigns a group named <Name> to that group, not tenant-wide' -ForEach @(@{ Name = 'AllDevices' }) {
        $null = Invoke-ExecAssignPolicy -Request (New-NamesRequest @($Name)) -TriggerMetadata $null

        Should -Invoke Set-CIPPAssignedPolicy -Times 1 -Exactly -ParameterFilter { (@($GroupIds) -join ',') -eq 'g-alldevices' -and -not $GroupName }
    }

    It 'refuses a name that matches <Expected>' -ForEach @(
        @{ Name = 'Missing'; Expected = 'no group'; Status = [System.Net.HttpStatusCode]::NotFound }
        @{ Name = 'Twice'; Expected = 'several groups'; Status = [System.Net.HttpStatusCode]::BadRequest }
    ) {
        $response = Invoke-ExecAssignPolicy -Request (New-NamesRequest @($Name)) -TriggerMetadata $null

        $response.StatusCode | Should -Be $Status
        $response.Body.Results | Should -BeLike "*Group*'$Name'*Policy not assigned*"
        Should -Invoke Set-CIPPAssignedPolicy -Times 0 -Exactly
    }
}
