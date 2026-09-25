BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCaseId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunSteps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecRunRequest.ps1')
}

Describe 'New-CIPPBecRunRequest requester address' {
    It 'records the address of the requesting technician on the case and the run item' {
        Mock Set-CIPPBecReport { $script:RequestProperties = $Properties }
        Mock New-CIPPAsyncDeployment { $JobId }
        $Prepared = New-CIPPBecRunRequest -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -RequestedBy 'tech@msp.com' -RequestedFromIP '192.0.2.77'
        $Prepared.Item.RequestedFromIP | Should -Be '192.0.2.77'
        $Prepared.Item.RequestedBy | Should -Be 'tech@msp.com'
        $script:RequestProperties.RequestedFromIP | Should -Be '192.0.2.77'
    }
}

Describe 'Get-CIPPBecRunSteps' {
    It 'defines the twelve phases of the investigation in order, with the score last' {
        $Steps = @(Get-CIPPBecRunSteps)
        $Steps.Key | Should -Be @('AuditLog', 'SignIns', 'MailboxRules', 'SentMail', 'Tenant', 'MailboxInventory', 'Grants', 'TransportRules', 'ReceivedMail', 'Directory', 'Activity', 'IPAnalysis', 'AttackerActivity', 'Score')
        $Steps | ForEach-Object { $_.Title | Should -Not -BeNullOrEmpty }
        @($Steps.Key | Select-Object -Unique).Count | Should -Be 14 -Because 'keys index the steps'
    }
}

Describe 'New-CIPPBecRunRequest' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPBecReport { $script:Rows.Add(@{ CaseId = $CaseId; Properties = $Properties; Replace = $Replace.IsPresent }) }
        $script:Jobs = [System.Collections.Generic.List[object]]::new()
        Mock New-CIPPAsyncDeployment { $script:Jobs.Add(@{ JobId = $JobId; Names = $Names; StepTitles = $StepTitles; Source = $Source }); $JobId }
    }

    It 'writes the Waiting history row, the queued progress job keyed on the case id, and returns the queue item' {
        $Prepared = New-CIPPBecRunRequest -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -DisplayName 'Victim' -RequestedBy 'tech@msp.com'
        $Prepared.CaseId | Should -Match '^BEC-'
        $script:Rows.Count | Should -Be 1
        $script:Rows[0].CaseId | Should -Be $Prepared.CaseId
        $script:Rows[0].Replace | Should -BeTrue
        $script:Rows[0].Properties.Status | Should -Be 'Waiting'
        $script:Rows[0].Properties.UserPrincipalName | Should -Be 'victim@contoso.com'
        $script:Rows[0].Properties.DisplayName | Should -Be 'Victim'
        $script:Rows[0].Properties.RequestedBy | Should -Be 'tech@msp.com'
        $script:Rows[0].Properties.ContainsKey('QueueId') | Should -BeFalse
        $script:Jobs.Count | Should -Be 1
        $script:Jobs[0].JobId | Should -Be $Prepared.CaseId -Because 'the page polls progress by case id'
        $script:Jobs[0].Names | Should -Be @('victim@contoso.com')
        $script:Jobs[0].Source | Should -Be 'BEC'
        @($script:Jobs[0].StepTitles).Count | Should -Be 14
        $Prepared.Item.FunctionName | Should -Be 'BECRun'
        $Prepared.Item.UserID | Should -Be 'u1'
        $Prepared.Item.userName | Should -Be 'victim@contoso.com'
        $Prepared.Item.CaseId | Should -Be $Prepared.CaseId
        $Prepared.Item.ContainsKey('QueueId') | Should -BeFalse
    }

    It 'carries the queue id for bulk runs and falls back to the object id as the progress name' {
        $Prepared = New-CIPPBecRunRequest -TenantFilter 'contoso.com' -UserId 'u2' -QueueId 'q-1'
        $script:Rows[0].Properties.QueueId | Should -Be 'q-1'
        $script:Jobs[0].Names | Should -Be @('u2')
        $Prepared.Item.QueueId | Should -Be 'q-1'
        $Prepared.Item.QueueName | Should -Be 'BEC investigation u2'
    }
}
