BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAutopilotconfig.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListAutopilotconfig.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
    . $FunctionPath

    function New-ListAPRequest {
        param($Type)
        [pscustomobject]@{
            Query = [pscustomobject]@{ TenantFilter = 'contoso.onmicrosoft.com'; type = $Type }
        }
    }

    function New-APProfile {
        param($Name, $Targets)
        [pscustomobject]@{
            id          = "$Name-id"
            displayName = $Name
            assignments = @($Targets | ForEach-Object { [pscustomobject]@{ target = $_ } })
        }
    }
}

Describe 'Invoke-ListAutopilotconfig ApProfile' {
    BeforeEach {
        $script:Profiles = @()
        $script:ProfileStatus = 200
        Mock New-GraphBulkRequest {
            @($Requests | ForEach-Object {
                    $Body = if ($_.id -eq 'Groups') {
                        [pscustomobject]@{ value = @([pscustomobject]@{ id = 'group-1'; displayName = 'Autopilot Devices' }) }
                    } elseif ($script:ProfileStatus -eq 200) {
                        [pscustomobject]@{ value = $script:Profiles }
                    } else {
                        [pscustomobject]@{ error = [pscustomobject]@{ message = 'Graph said no' } }
                    }
                    [pscustomobject]@{
                        id     = $_.id
                        status = if ($_.id -eq 'Groups') { 200 } else { $script:ProfileStatus }
                        body   = $Body
                    }
                })
        }
        Mock New-GraphGetRequest { @() }
    }

    It 'resolves group assignment targets to display names' {
        $script:Profiles = @(
            (New-APProfile -Name 'Standard' -Targets @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'group-1' }
                )),
            (New-APProfile -Name 'Kiosk' -Targets @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
                ))
        )

        $Response = Invoke-ListAutopilotconfig -Request (New-ListAPRequest -Type 'ApProfile') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body | Should -HaveCount 2
        ($Response.Body | Where-Object displayName -EQ 'Standard').PolicyAssignment | Should -Be 'Autopilot Devices'
        ($Response.Body | Where-Object displayName -EQ 'Kiosk').PolicyAssignment | Should -Be 'All Devices'
        $Response.Body.PolicyTypeName | Select-Object -Unique | Should -Be 'Autopilot Profile'
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $tenantid -eq 'contoso.onmicrosoft.com' -and
            ($Requests.url -join ' ') -like '*windowsAutopilotDeploymentProfiles?$expand=assignments*' -and
            ($Requests.url -join ' ') -like '*/groups?*select=id,displayName*'
        }
        Should -Not -Invoke New-GraphGetRequest
    }

    It 'leaves the name blank for a deleted group and keeps the raw assignments' {
        $script:Profiles = @(
            (New-APProfile -Name 'Orphaned' -Targets @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'gone-group' }
                ))
        )

        $Response = Invoke-ListAutopilotconfig -Request (New-ListAPRequest -Type 'ApProfile') -TriggerMetadata $null

        $Response.Body | Should -HaveCount 1
        $Response.Body[0].PolicyAssignment | Should -BeNullOrEmpty
        $Response.Body[0].assignments[0].target.groupId | Should -Be 'gone-group'
    }

    It 'returns an empty body when the tenant has no profiles' {
        $Response = Invoke-ListAutopilotconfig -Request (New-ListAPRequest -Type 'ApProfile') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        @($Response.Body) | Should -HaveCount 0
    }

    It 'surfaces a Graph error on the profile request as Forbidden' {
        $script:ProfileStatus = 403

        $Response = Invoke-ListAutopilotconfig -Request (New-ListAPRequest -Type 'ApProfile') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::Forbidden)
        $Response.Body | Should -Be 'Graph said no'
    }
}

Describe 'Invoke-ListAutopilotconfig ESP' {
    It 'still uses the single Graph GET for enrollment status pages' {
        Mock New-GraphBulkRequest { throw 'should not batch for ESP' }
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration'; displayName = 'ESP' },
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentLimitConfiguration'; displayName = 'Limit' }
            )
        }

        $Response = Invoke-ListAutopilotconfig -Request (New-ListAPRequest -Type 'ESP') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.displayName | Should -Be 'ESP'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*deviceEnrollmentConfigurations*' }
    }
}
