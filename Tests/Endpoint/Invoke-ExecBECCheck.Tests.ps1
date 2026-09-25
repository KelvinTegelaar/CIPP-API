BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function New-CIPPBecCaseId { 'BEC-20260820120000-new001' }
    function Start-CIPPOrchestrator { param($InputObjectGuid, $InputObject, [switch]$CallerIsQueueTrigger) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) $JobId }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunSteps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecRunRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECCheck.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Query = @{}, $Body = $null)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECCheck' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')); 'x-forwarded-for' = '[2001:db8::77]:51000, 10.0.0.1' }
            Query   = [pscustomobject]$Query
            Body    = $Body
        }
    }
    $script:Completed = [pscustomobject]@{ CaseId = 'BEC-20260810000000-old001'; RowKey = 'BEC-20260810000000-old001'; Status = 'Completed'; Scope = 'Quick'; ExtractedAt = '2026-08-10T00:10:00Z'; RequestedBy = 'tech@msp.com'; Containment = @(); EvidenceSha256 = $null; EvidenceCreatedAt = $null; Results = [pscustomobject]@{ CaseId = 'BEC-20260810000000-old001'; NewRules = @() } }
}

Describe 'Invoke-ExecBECCheck' {
    BeforeEach {
        Mock Set-CIPPBecReport { }
        Mock Start-CIPPOrchestrator { }
        Mock New-CIPPAsyncDeployment { $JobId }
        Mock Get-CIPPAsyncDeployment { @() }
        Mock Set-CIPPAsyncDeploymentStatus { }
        Mock Set-CIPPAsyncDeploymentStep { }
        Mock Write-LogMessage { }
    }

    Context 'loading the page (GET without a GUID never starts a run)' {
        It 'reports that the user has no runs, and queues nothing' {
            Mock Get-CIPPBecReport { @() }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; userName = 'user@contoso.com' }) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            $Response.Body.GUID | Should -BeNullOrEmpty
            $Response.Body.NoRuns | Should -BeTrue
            Should -Invoke Start-CIPPOrchestrator -Times 0
            Should -Invoke Set-CIPPBecReport -Times 0
        }

        It 'returns the latest existing run without queueing' {
            Mock Get-CIPPBecReport { @($script:Completed) }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; userName = 'user@contoso.com' }) -TriggerMetadata $null
            $Response.Body.GUID | Should -Be 'BEC-20260810000000-old001'
            $Response.Body.Status | Should -Be 'Completed'
            Should -Invoke Start-CIPPOrchestrator -Times 0
            Should -Invoke Set-CIPPBecReport -Times 0
        }

        It 'ignores failed runs when looking for the latest, still without queueing' {
            Mock Get-CIPPBecReport { @([pscustomobject]@{ CaseId = 'BEC-x'; Status = 'Error' }) }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; userName = 'user@contoso.com' }) -TriggerMetadata $null
            $Response.Body.NoRuns | Should -BeTrue
            Should -Invoke Start-CIPPOrchestrator -Times 0
        }

        It 'fails cleanly without a userid' {
            Mock Get-CIPPBecReport { @() }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 500
            $Response.Body.Error | Should -Match 'userid'
        }
    }

    Context 'starting a run' {
        It 'POST queues the investigation: history row, progress job keyed on the case id, orchestration, and returns the case id as GUID' {
            Mock Get-CIPPBecReport { @($script:Completed) }
            $Response = Invoke-ExecBECCheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; userid = 'u1'; userName = 'user@contoso.com' })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            $Response.Body.GUID | Should -Be 'BEC-20260820120000-new001'
            $Response.Body.Status | Should -Be 'Waiting'
            Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { $Replace.IsPresent -and $Properties.Status -eq 'Waiting' -and $Properties.UserId -eq 'u1' -and $Properties.RequestedBy -eq 'tech@msp.com' -and $CaseId -eq 'BEC-20260820120000-new001' }
            Should -Invoke New-CIPPAsyncDeployment -Times 1 -ParameterFilter { $JobId -eq 'BEC-20260820120000-new001' -and $Names -contains 'user@contoso.com' -and @($StepTitles).Count -eq 14 -and $Source -eq 'BEC' }
            Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter { $InputObject.OrchestratorName -eq 'BECRunOrchestrator' -and $InputObject.Batch[0].FunctionName -eq 'BECRun' -and $InputObject.Batch[0].CaseId -eq 'BEC-20260820120000-new001' -and $InputObject.Batch[0].UserID -eq 'u1' -and $InputObject.Batch[0].RequestedFromIP -eq '2001:db8::77' }
            Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { $Properties.RequestedFromIP -eq '2001:db8::77' } -Because "the requester's first x-forwarded-for hop, without port or brackets, is recorded as the technician's address"
        }

        It 'POST without a userid fails cleanly and queues nothing' {
            $Response = Invoke-ExecBECCheck -Request (New-Request -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; userid = '' })) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 500
            Should -Invoke Start-CIPPOrchestrator -Times 0
        }
    }

    Context 'polling a run' {
        It 'reports Waiting with the live progress while the run is queued or running' {
            $Started = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('o')
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-w'; Status = 'Running'; Scope = 'Full'; RequestedAt = (Get-Date).ToUniversalTime().AddMinutes(-3).ToString('o'); RequestedBy = 'tech@msp.com'; StartedAt = $Started } }
            Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Name = 'user@contoso.com'; Status = 'running'; LastUpdate = [DateTimeOffset]::UtcNow.AddMinutes(-1); Steps = @([pscustomobject]@{ Title = 'Audit log'; Status = 'succeeded'; Message = 'Done' }, [pscustomobject]@{ Title = 'Sign-ins'; Status = 'running'; Message = 'Reading sign-ins' }); Logs = '' }) }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-w' }) -TriggerMetadata $null
            $Response.Body.Waiting | Should -BeTrue
            $Response.Body.CaseId | Should -Be 'BEC-w'
            $Response.Body.Status | Should -Be 'Running'
            $Response.Body.StartedAt | Should -Be $Started
            $Response.Body.Progress.Status | Should -Be 'running'
            @($Response.Body.Progress.Steps).Count | Should -Be 2
            $Response.Body.Progress.Steps[1].Status | Should -Be 'running'
            Should -Invoke Get-CIPPBecReport -Times 1 -ParameterFilter { $CaseId -eq 'BEC-w' -and $IncludeResults.IsPresent }
            Should -Invoke Get-CIPPAsyncDeployment -Times 1 -ParameterFilter { $JobId -eq 'BEC-w' }
            Should -Invoke Set-CIPPBecReport -Times 0 -Because 'a run that progressed a minute ago is not stale'
        }

        It 'marks a run with no progress for longer than 20 minutes as failed, on the job rows too, and says why' {
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-stale'; Status = 'Running'; Scope = 'Full'; RequestedAt = (Get-Date).ToUniversalTime().AddMinutes(-50).ToString('o'); StartedAt = (Get-Date).ToUniversalTime().AddMinutes(-45).ToString('o') } }
            Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Name = 'user@contoso.com'; Status = 'running'; LastUpdate = [DateTimeOffset]::UtcNow.AddMinutes(-35); Steps = @([pscustomobject]@{ Title = 'Audit log'; Status = 'succeeded'; Message = 'Done' }, [pscustomobject]@{ Title = 'Sign-ins'; Status = 'running'; Message = 'Reading sign-ins' }); Logs = '' }) }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-stale' }) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            $Response.Body.Waiting | Should -BeFalse
            $Response.Body.Status | Should -Be 'Error'
            $Response.Body.Error | Should -Match 'No progress for more than 20 minutes'
            Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { $CaseId -eq 'BEC-stale' -and $Properties.Status -eq 'Error' -and $Properties.ErrorMessage -match 'No progress' }
            Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -ParameterFilter { $JobId -eq 'BEC-stale' -and $StepIndex -eq 1 -and $StepStatus -eq 'failed' }
            Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -ParameterFilter { $JobId -eq 'BEC-stale' -and $Status -eq 'failed' }
            Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $message -match 'marked failed' }
        }

        It 'judges a queued run with no job rows by when it was requested' {
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-q'; Status = 'Waiting'; Scope = 'Full'; RequestedAt = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o') } }
            Mock Get-CIPPAsyncDeployment { @() }
            (Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-q' }) -TriggerMetadata $null).Body.Waiting | Should -BeTrue
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-q'; Status = 'Waiting'; Scope = 'Full'; RequestedAt = (Get-Date).ToUniversalTime().AddMinutes(-25).ToString('o') } }
            $Old = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-q' }) -TriggerMetadata $null
            $Old.Body.Waiting | Should -BeFalse
            $Old.Body.Error | Should -Match 'abandoned'
            Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 0 -Because 'there are no job rows to mark'
        }

        It 'reports Waiting without progress when the job rows are missing' {
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-w'; Status = 'Waiting'; Scope = 'Quick' } }
            Mock Get-CIPPAsyncDeployment { @() }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-w' }) -TriggerMetadata $null
            $Response.Body.Waiting | Should -BeTrue
            $Response.Body.Progress | Should -BeNullOrEmpty
        }

        It 'returns the results payload with a Run header once completed' {
            Mock Get-CIPPBecReport { $script:Completed }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-20260810000000-old001' }) -TriggerMetadata $null
            $Response.Body.CaseId | Should -Be 'BEC-20260810000000-old001'
            $Response.Body.Run.Status | Should -Be 'Completed'
            $Response.Body.Run.RequestedBy | Should -Be 'tech@msp.com'
            $Response.Body.PSObject.Properties.Name | Should -Contain 'NewRules'
        }

        It 'accepts caseId as the explicit form of GUID' {
            Mock Get-CIPPBecReport { $script:Completed }
            $Response = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-20260810000000-old001' }) -TriggerMetadata $null
            $Response.Body.Run.CaseId | Should -Be 'BEC-20260810000000-old001'
        }

        It 'surfaces a failed run and an unknown case id as errors, not as Waiting' {
            Mock Get-CIPPBecReport { [pscustomobject]@{ CaseId = 'BEC-e'; Status = 'Error'; ErrorMessage = 'boom'; Scope = 'Quick' } }
            Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Name = 'user@contoso.com'; Status = 'failed'; Steps = @([pscustomobject]@{ Title = 'Audit log'; Status = 'failed'; Message = 'boom' }); Logs = 'boom' }) }
            $Failed = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-e' }) -TriggerMetadata $null
            $Failed.Body.Waiting | Should -BeFalse
            $Failed.Body.Error | Should -Be 'boom'
            $Failed.Body.Progress.Status | Should -Be 'failed' -Because 'the page shows which phase failed'
            Mock Get-CIPPBecReport { $null }
            $Missing = Invoke-ExecBECCheck -Request (New-Request @{ tenantFilter = 'contoso.com'; GUID = 'BEC-missing' }) -TriggerMetadata $null
            $Missing.Body.Waiting | Should -BeFalse
            $Missing.Body.Error | Should -Match 'not found'
        }
    }
}
