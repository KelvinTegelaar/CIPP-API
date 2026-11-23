BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    $FunctionPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-ExecRemoveAppAssignment.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $Modules 'CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . $FunctionPath

    function Invoke-Remove {
        param([hashtable]$Body)
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecRemoveAppAssignment' }; Headers = @{}; Body = [pscustomobject]$Body }
        Invoke-ExecRemoveAppAssignment -Request $Request -TriggerMetadata $null
    }

    $script:Assignments = @(
        [pscustomobject]@{ id = 'a1'; intent = 'required'; source = 'direct'
            target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
            settings = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.win32LobAppAssignmentSettings'; notifications = 'showAll' }
        }
        [pscustomobject]@{ id = 'a2'; intent = 'required'; source = 'direct'
            target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' }
            settings = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.win32LobAppAssignmentSettings'; notifications = 'hideAll' }
        }
        [pscustomobject]@{ id = 'a3'; intent = 'required'; source = 'direct'
            target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'; groupId = 'g2' }
            settings = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.win32LobAppAssignmentSettings' }
        }
    )
}

Describe 'Invoke-ExecRemoveAppAssignment' {
    BeforeEach {
        $script:PostedBody = $null
        Mock New-GraphGetRequest { $script:Assignments }
        Mock New-GraphPOSTRequest { $script:PostedBody = $body | ConvertFrom-Json }
    }

    It 'drops only the chosen assignment and re-sends the rest to the assign action' {
        $Response = Invoke-Remove @{ tenantFilter = 'contoso.com'; ID = 'app1'; AssignmentId = 'a1' }

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/app1/assign' -and $tenantid -eq 'contoso.com'
        }
        $Kept = @($script:PostedBody.mobileAppAssignments)
        $Kept.Count | Should -Be 2
        $Kept.target.groupId | Should -Be @('g1', 'g2')
        $Kept[0].settings.notifications | Should -Be 'hideAll'
        $Kept[0].'@odata.type' | Should -Be '#microsoft.graph.mobileAppAssignment'
    }

    It 'leaves settings off a kept exclusion, which Graph rejects' {
        $null = Invoke-Remove @{ tenantFilter = 'contoso.com'; ID = 'app1'; AssignmentId = 'a2' }

        $Exclusion = @($script:PostedBody.mobileAppAssignments)[1]
        $Exclusion.target.'@odata.type' | Should -Be '#microsoft.graph.exclusionGroupAssignmentTarget'
        $Exclusion.PSObject.Properties.Name | Should -Not -Contain 'settings'
    }

    It 'sends an empty list when the last assignment is removed' {
        Mock New-GraphGetRequest { $script:Assignments[0] }

        $Response = Invoke-Remove @{ tenantFilter = 'contoso.com'; ID = 'app1'; AssignmentId = 'a1' }

        $Response.StatusCode | Should -Be 200
        @($script:PostedBody.mobileAppAssignments).Count | Should -Be 0
        $script:PostedBody.PSObject.Properties.Name | Should -Contain 'mobileAppAssignments'
    }

    It 'returns 404 without writing when the assignment is gone' {
        $Response = Invoke-Remove @{ tenantFilter = 'contoso.com'; ID = 'app1'; AssignmentId = 'missing' }

        $Response.StatusCode | Should -Be 404
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'does not write when the current assignments cannot be read' {
        Mock New-GraphGetRequest { throw 'Forbidden' }

        $Response = Invoke-Remove @{ tenantFilter = 'contoso.com'; ID = 'app1'; AssignmentId = 'a1' }

        $Response.StatusCode | Should -Be 500
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'rejects a request missing <Missing>' -ForEach @(
        @{ Missing = 'ID'; Body = @{ tenantFilter = 'contoso.com'; AssignmentId = 'a1' } }
        @{ Missing = 'AssignmentId'; Body = @{ tenantFilter = 'contoso.com'; ID = 'app1' } }
    ) {
        $Response = Invoke-Remove $Body

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
