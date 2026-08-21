BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAssignAutopilotProfile.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecAssignAutopilotProfile.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGETRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    function New-AssignAPRequest {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignAutopilotProfile' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecAssignAutopilotProfile' {
    BeforeEach {
        Mock -CommandName New-GraphGETRequest -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { $null }
        Mock -CommandName Write-LogMessage
    }

    It 'assigns AllDevices when no existing assignment' {
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'AllDevices' }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $res.Body.Results | Should -BeLike '*Successfully*all devices*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $body -like '*allDevicesAssignmentTarget*'
        }
    }

    It 'skips AllDevices when already assigned' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @([pscustomobject]@{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } })
        }
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'AllDevices' }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $res.Body.Results | Should -BeLike '*already assigned*'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'assigns new groups and skips duplicates' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @([pscustomobject]@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'existing-1' } })
        }
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'customGroup'; GroupIds = @('existing-1', 'new-1', 'new-2') }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 2
    }

    It 'normalizes option objects to bare ids' {
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'customGroup'; GroupIds = @(@{ value = 'g1'; label = 'Group 1' }) }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $body -like '*g1*'
        }
    }

    It 'returns error when ProfileId is missing' {
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; AssignTo = 'AllDevices' }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $res.Body.Results | Should -BeLike '*Profile ID*'
    }

    It 'returns error when no group ids provided for customGroup' {
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'customGroup'; GroupIds = @() }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $res.Body.Results | Should -BeLike '*at least one group*'
    }

    It 'RemoveAll deletes all existing assignments' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'a1'; target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } },
                [pscustomobject]@{ id = 'a2'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }
            )
        }
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'RemoveAll' }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $res.Body.Results | Should -BeLike '*removed all 2*'
        Should -Invoke New-GraphPOSTRequest -Times 2 -ParameterFilter { $type -eq 'DELETE' }
    }

    It 'RemoveAll reports no assignments when empty' {
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'RemoveAll' }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $res.Body.Results | Should -BeLike '*no assignments*'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'RemoveGroups removes only matching assignments' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'a1'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } },
                [pscustomobject]@{ id = 'a2'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g2' } },
                [pscustomobject]@{ id = 'a3'; target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
            )
        }
        $req = New-AssignAPRequest @{ tenantFilter = 't1'; ProfileId = 'p1'; ProfileName = 'Test'; AssignTo = 'RemoveGroups'; GroupIds = @('g1', 'allDevices') }
        $res = Invoke-ExecAssignAutopilotProfile -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $res.Body.Results | Should -BeLike '*removed 2*'
        Should -Invoke New-GraphPOSTRequest -Times 2 -ParameterFilter { $type -eq 'DELETE' }
    }
}
