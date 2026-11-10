BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPBecReport { param($Kind, $TenantFilter, $CaseId, $ServicePrincipalId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($Kind, $TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function New-CIPPBecCaseId { param($Prefix) "$Prefix-20261105120000-new001" }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) $JobId }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function Add-CIPPRealtimeWatch { param($JobId) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/Get-CIPPNhiRunSteps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/New-CIPPNhiRunRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecNHICheck.ps1' | Select-Object -First 1).FullName

    function New-Request {
        param([hashtable]$Query = @{}, $Body = $null)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecNHICheck' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')); 'x-forwarded-for' = '203.0.113.50:51000, 10.0.0.1' }
            Query   = [pscustomobject]$Query
            Body    = $Body
        }
    }
    $script:SpA = '0b6b8c2e-1111-4a4a-9b9b-000000000001'
    $script:SpB = '0b6b8c2e-1111-4a4a-9b9b-000000000002'
}

Describe 'Invoke-ExecNHICheck' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPBecReport { $script:Rows.Add(@{ Kind = $Kind; CaseId = $CaseId; Properties = $Properties }) }
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = ($uri -replace '^.*/servicePrincipals/([^?]+)\?.*$', '$1'); appId = 'app-1'; displayName = 'Invoice Sync'; servicePrincipalType = 'Application' } }
        Mock Write-LogMessage { }
        Mock Add-CIPPRealtimeWatch { }
        Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Status = 'running'; Steps = @() }) }
    }

    It 'starts one sequential run for the app, as the technician, from their address' {
        $Response = Invoke-ExecNHICheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; servicePrincipalId = $script:SpA })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.CaseId | Should -BeExactly 'NHI-20261105120000-new001'
        $script:Rows[0].Kind | Should -BeExactly 'NHI'
        $script:Rows[0].Properties.Status | Should -BeExactly 'Waiting'
        $script:Rows[0].Properties.RequestedBy | Should -BeExactly 'tech@msp.com'
        $script:Rows[0].Properties.RequestedFromIP | Should -BeExactly '203.0.113.50'
        $Orchestration = $script:Started[0]
        $Orchestration.Sequential | Should -BeTrue
        @($Orchestration.Batch).Count | Should -Be @(Get-CIPPNhiRunSteps).Count
        $Orchestration.Batch[0].FunctionName | Should -BeExactly 'NHIRun'
        $Orchestration.Batch[-1].Step | Should -BeExactly 'Score'
    }

    It 'starts one run per app for several apps and reports the ones that could not start' {
        Mock New-GraphGetRequest { throw 'Resource does not exist' } -ParameterFilter { $uri -like "*$script:SpB*" }

        $Response = Invoke-ExecNHICheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; servicePrincipalIds = @(@{ value = $script:SpA }, $script:SpB) })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 207
        @($Response.Body.Cases).Count | Should -Be 2
        ($Response.Body.Cases | Where-Object ServicePrincipalId -EQ $script:SpB).Status | Should -BeExactly 'Error'
        $script:Started.Count | Should -Be 1
    }

    It 'refuses an id that is not a GUID and every tenant at once' {
        (Invoke-ExecNHICheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; servicePrincipalId = "x' or 1 eq 1" })) -TriggerMetadata $null).StatusCode | Should -Be 400
        (Invoke-ExecNHICheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'AllTenants'; servicePrincipalId = $script:SpA })) -TriggerMetadata $null).StatusCode | Should -Be 400
        $script:Started.Count | Should -Be 0
    }

    It 'answers 404 for a case that does not exist' {
        Mock Get-CIPPBecReport { $null }
        (Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'NHI-missing' }) -TriggerMetadata $null).StatusCode | Should -Be 404
    }

    It 'reads a case named in the body, as MCP sends it, without starting a run' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Completed'; Results = [pscustomobject]@{ CaseId = 'NHI-1' } } }

        $Response = Invoke-ExecNHICheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; caseId = 'NHI-1' })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Run.CaseId | Should -BeExactly 'NHI-1'
        $script:Started.Count | Should -Be 0
    }

    It 'fails a run that made no progress for hours, so the app can be investigated again' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Running'; RequestedAt = [datetime]::UtcNow.AddDays(-1).ToString('o') } }
        Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Status = 'running'; Steps = @(); LastUpdate = [System.DateTimeOffset]::UtcNow.AddHours(-7) }) }

        $Response = Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'NHI-1' }) -TriggerMetadata $null

        $Response.Body.Waiting | Should -BeFalse
        $Response.Body.Error | Should -BeLike '*stopped before it finished*'
        $script:Rows[0].Properties.Status | Should -BeExactly 'Error'

        Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Status = 'running'; Steps = @(); LastUpdate = [System.DateTimeOffset]::UtcNow.AddMinutes(-5) }) }
        (Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'NHI-1' }) -TriggerMetadata $null).Body.Waiting | Should -BeTrue -Because 'recent progress means the run is alive'
    }

    It 'returns progress while a run is going and the payload with its run block when done' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Running'; DisplayName = 'Invoice Sync' } }
        $Waiting = Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'NHI-1' }) -TriggerMetadata $null
        $Waiting.Body.Waiting | Should -BeTrue
        $Waiting.Body.Progress.Status | Should -BeExactly 'running'

        Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Completed'; Containment = @([pscustomobject]@{ Kind = 'Containment' }); Results = [pscustomobject]@{ CaseId = 'NHI-1'; Score = [pscustomobject]@{ Level = 'High' } } } }
        $Done = Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'NHI-1' }) -TriggerMetadata $null
        $Done.Body.Score.Level | Should -BeExactly 'High'
        @($Done.Body.Run.Containment).Count | Should -Be 1
        Should -Invoke Get-CIPPBecReport -ParameterFilter { $Kind -eq 'NHI' -and $IncludeResults }
    }

    It 'returns the app''s latest run without starting one' {
        Mock Get-CIPPBecReport { @([pscustomobject]@{ CaseId = 'NHI-2'; Status = 'Error' }, [pscustomobject]@{ CaseId = 'NHI-1'; Status = 'Completed' }) }

        $Response = Invoke-ExecNHICheck -Request (New-Request @{ tenantFilter = 'contoso.com'; servicePrincipalId = $script:SpA }) -TriggerMetadata $null

        $Response.Body.CaseId | Should -BeExactly 'NHI-1'
        $script:Started.Count | Should -Be 0
        Should -Invoke Get-CIPPBecReport -ParameterFilter { $ServicePrincipalId -eq $script:SpA }
    }
}
