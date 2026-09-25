BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function Start-CIPPOrchestrator { param($InputObjectGuid, $InputObject, [switch]$CallerIsQueueTrigger) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) $JobId }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCaseId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunSteps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecRunRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECBulkCheck.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param($Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECBulkCheck' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')) }
            Query   = $null
            Body    = $Body
        }
    }
    $script:Users = @{
        'u1' = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'a@contoso.com'; displayName = 'A' }
        'u2' = [pscustomobject]@{ id = 'u2'; userPrincipalName = 'b@contoso.com'; displayName = 'B' }
        'u3' = [pscustomobject]@{ id = 'u3'; userPrincipalName = 'c@contoso.com'; displayName = 'C' }
    }
}

Describe 'Invoke-ExecBECBulkCheck' {
    BeforeEach {
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $Ids = [regex]::Matches($Request.url, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
                [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @($Ids | ForEach-Object { $script:Users[$_] } | Where-Object { $_ }) } }
            }
        }
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPBecReport { $script:Rows.Add(@{ CaseId = $CaseId; Properties = $Properties; Replace = $Replace.IsPresent }) }
        $script:Orchestrations = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Orchestrations.Add($InputObject) }
        Mock Write-LogMessage { }
    }

    It 'queues one run per selected user from the bulk (array) body with the chosen scope' {
        $Body = @(
            [pscustomobject]@{ UserIds = 'u1'; tenantFilter = 'contoso.com'; Scope = [pscustomobject]@{ label = 'Full'; value = 'Full' } }
            [pscustomobject]@{ UserIds = 'u2'; tenantFilter = 'contoso.com'; Scope = [pscustomobject]@{ label = 'Full'; value = 'Full' } }
        )
        $Response = Invoke-ExecBECBulkCheck -Request (New-Request $Body) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.QueueId | Should -Be 'queue-1'
        $Response.Body.Cases.Count | Should -Be 2
        $Response.Body.Cases[0].CaseId | Should -Match '^BEC-'
        $script:Rows.Count | Should -Be 2
        $script:Rows[0].Replace | Should -BeTrue
        $script:Rows[0].Properties.Status | Should -Be 'Waiting'
        $script:Rows[0].Properties.QueueId | Should -Be 'queue-1'
        $script:Rows[0].Properties.RequestedBy | Should -Be 'tech@msp.com'
        $script:Orchestrations.Count | Should -Be 1
        $Batch = @($script:Orchestrations[0].Batch)
        $Batch.Count | Should -Be 2
        $Batch[0].FunctionName | Should -Be 'BECRun'
        $Batch[0].QueueId | Should -Be 'queue-1'
        $Batch[0].userName | Should -Be 'a@contoso.com'
        $Batch[0].CaseId | Should -Be $script:Rows[0].CaseId
        Should -Invoke New-CippQueueEntry -Times 1 -ParameterFilter { $TotalTasks -eq 2 }
    }

    It 'accepts a single object with UserIds[] and always queues the full investigation' {
        $Response = Invoke-ExecBECBulkCheck -Request (New-Request ([pscustomobject]@{ tenantFilter = 'contoso.com'; UserIds = @('u1', 'u3', 'u1'); Scope = 'Quick' })) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        @($script:Orchestrations[0].Batch).Count | Should -Be 2 -Because 'duplicates are collapsed'
        $Response.Body.Results | Should -Match 'Queued 2 BEC investigation'
    }

    It 'reports users it cannot resolve and queues the rest' {
        $Response = Invoke-ExecBECBulkCheck -Request (New-Request ([pscustomobject]@{ tenantFilter = 'contoso.com'; UserIds = @('u1', 'ghost') })) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        ($Response.Body.Cases | Where-Object { $_.UserId -eq 'ghost' }).Error | Should -Be 'User not found'
        @($script:Orchestrations[0].Batch).Count | Should -Be 1
    }

    It 'does not cap the user count - a list over 50 is accepted and every resolvable user is queued' {
        $Response = Invoke-ExecBECBulkCheck -Request (New-Request ([pscustomobject]@{ tenantFilter = 'contoso.com'; UserIds = @(1..51 | ForEach-Object { "u$_" }) })) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        # only u1/u2/u3 resolve in the mock; the other 48 are reported as not found, none refused
        @($script:Orchestrations[0].Batch).Count | Should -Be 3
        @($Response.Body.Cases | Where-Object { $_.Error -eq 'User not found' }).Count | Should -Be 48
        $Response.Body.Results | Should -Match '48 selected user\(s\) could not be found and were skipped'
    }

    It 'refuses an empty selection without queueing anything' {
        $None = Invoke-ExecBECBulkCheck -Request (New-Request ([pscustomobject]@{ tenantFilter = 'contoso.com'; UserIds = @() })) -TriggerMetadata $null
        $None.StatusCode | Should -Be 500
        $None.Body.Results | Should -Match 'No users'
        $script:Orchestrations.Count | Should -Be 0
        $script:Rows.Count | Should -Be 0
    }
}
