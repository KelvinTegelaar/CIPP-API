BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CIPPBaseline { param($ID, [switch]$ResolveIdentityLabels) }
    function New-CIPPBaseline { param($Baseline, $User, $Source, $SHA, $SourcePath, [bool]$LocalChanges) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPBaselineOutOfScopeAssignment { param($Assignments) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecMoveBaselineStandards.ps1')

    $script:Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@example.com"}'))
    $script:NewRequest = {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecMoveBaselineStandards' }
            Headers = @{ 'x-ms-client-principal' = $script:Principal }
            Body    = ($Body | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        }
    }
    $script:Config = {
        param($Instance, $Variables = @{})
        [pscustomobject]@{ standard = ($Instance -split '#')[0]; instance = $Instance; variables = [pscustomobject]$Variables; remediateEnabled = $true; alertEnabled = $true; alertOnRemediate = $false }
    }
    $script:Stage = {
        param($Name, $Configs, $Conditions = @())
        [pscustomobject]@{
            name = $Name; logic = 'and'; conditions = @($Conditions)
            conditionGroups = @([pscustomobject]@{ logic = 'or'; conditions = @([pscustomobject]@{ type = 'manual' }) })
            standards = @($Configs.instance); standardsConfig = @($Configs)
        }
    }
}

Describe 'Invoke-ExecMoveBaselineStandards' {
    BeforeEach {
        $script:Saved = [System.Collections.Generic.List[object]]::new()
        $script:SaveFailsFor = $null
        $script:OutOfScope = @{}
        $Time = [pscustomobject]@{ type = 'time'; days = 7; unit = 'days' }
        $script:Baselines = @{
            'src' = [pscustomobject]@{
                GUID = 'src'; templateName = 'Source'; description = 'from'; source = $null
                assignments = @([pscustomobject]@{ label = 'Contoso'; value = 'contoso.com'; type = 'Tenant' })
                exclusions = @(); alertEmails = 'a@b.c'; alertWebhookUrl = ''; disableAlerts = $false; disableScheduledRuns = $true
                stages = @(
                    (& $script:Stage 'Pilot' @((& $script:Config 'DisableGuests' @{ x = 1 }), (& $script:Config 'SafeLinks#abc12345' @{ name = 'p' })))
                    (& $script:Stage 'Wide' @((& $script:Config 'AuditLog')) @($Time))
                    (& $script:Stage 'Last' @((& $script:Config 'Branding')) @($Time))
                )
            }
            'tgt' = [pscustomobject]@{
                GUID = 'tgt'; templateName = 'Target'; description = 'to'; source = 'Org/repo'
                assignments = @([pscustomobject]@{ label = 'Fabrikam'; value = 'fabrikam.com'; type = 'Tenant' })
                exclusions = @([pscustomobject]@{ label = 'Old'; value = 'old.com' }); alertEmails = ''; alertWebhookUrl = 'https://hook'; disableAlerts = $true; disableScheduledRuns = $false
                stages = @(
                    (& $script:Stage 'One' @((& $script:Config 'AuditLog')))
                    (& $script:Stage 'Two' @((& $script:Config 'DisableGuests')) @($Time))
                )
            }
        }
        Mock Get-CIPPBaseline { $script:Baselines[$ID] }
        Mock Get-CIPPBaselineDefinition { @([pscustomobject]@{ name = 'SafeLinks'; multiple = $true }, [pscustomobject]@{ name = 'DisableGuests'; label = 'Disable Guests'; multiple = $false }) }
        Mock Get-CIPPBaselineOutOfScopeAssignment { foreach ($A in $Assignments) { if ($script:OutOfScope[$A.value]) { $script:OutOfScope[$A.value] } } }
        Mock New-CIPPBaseline {
            if ($Baseline.GUID -eq $script:SaveFailsFor) { throw 'table write failed' }
            $script:Saved.Add([pscustomobject]@{ Baseline = $Baseline; LocalChanges = $PesterBoundParameters.ContainsKey('LocalChanges') ? $LocalChanges : $null })
        }
        Mock Write-LogMessage { }
    }

    It 'moves a standard: target first, then source without it' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 0 })
        $R.StatusCode | Should -Be 200
        $R.Body.Results | Should -Match '^Moved Branding from Source to stage 1 of Target'
        $script:Saved.Count | Should -Be 2
        $script:Saved[0].Baseline.GUID | Should -Be 'tgt'
        @($script:Saved[0].Baseline.stages[0].standards.instance) | Should -Be @('AuditLog', 'Branding')
        $script:Saved[0].LocalChanges | Should -Be $true
        $script:Saved[1].Baseline.GUID | Should -Be 'src'
        @($script:Saved[1].Baseline.stages[2].standards).Count | Should -Be 0
        $script:Saved[1].Baseline.stages.Count | Should -Be 3
        $script:Saved[1].LocalChanges | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 2 -ParameterFilter { $Sev -eq 'Info' }
    }

    It 'copies a standard and leaves the source alone, keeping its settings' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; mode = 'copy'; standard = 'Branding'; sourceStage = 2; targetStage = 1 })
        $R.StatusCode | Should -Be 200
        $script:Saved.Count | Should -Be 1
        $Copied = $script:Saved[0].Baseline.stages[1].standards[1]
        $Copied.instance | Should -Be 'Branding'
        $Copied.remediateEnabled | Should -Be $true
    }

    It 'gives a multi-instance standard a new instance id in the target' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'SafeLinks#abc12345'; sourceStage = 0; targetStage = 0 })
        $R.StatusCode | Should -Be 200
        $Copied = $script:Saved[0].Baseline.stages[0].standards[1]
        $Copied.standard | Should -Be 'SafeLinks'
        $Copied.instance | Should -Match '^SafeLinks#[0-9a-f]{8}$'
        $Copied.instance | Should -Not -Be 'SafeLinks#abc12345'
        $Copied.variables.name | Should -Be 'p'
        @($script:Saved[1].Baseline.stages[0].standards.instance) | Should -Be @('DisableGuests')
    }

    It 'refuses a single-instance standard the target stage already has, and writes nothing' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'DisableGuests'; sourceStage = 0; targetStage = 1 })
        $R.StatusCode | Should -Be 400
        $R.Body.Results | Should -Match 'already has DisableGuests'
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'appends a whole stage as a new last stage by default, keeping its name and conditions, and removes it from the source' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; stage = 1 })
        $R.StatusCode | Should -Be 200
        $R.Body.Results | Should -Not -Match 'no graduation conditions'
        $Tgt = $script:Saved[0].Baseline
        @($Tgt.stages.name) | Should -Be @('One', 'Two', 'Wide')
        $New = $Tgt.stages[2]
        $New.logic | Should -Be 'and'
        $New.conditions[0].type | Should -Be 'time'
        $New.conditions[0].days | Should -Be 7
        $New.conditionGroups[0].conditions[0].type | Should -Be 'manual'
        @($New.standards.instance) | Should -Be @('AuditLog')
        @($Tgt.stages.sourceStage) | Should -Be @(1, 2, 3)
        $Src = $script:Saved[1].Baseline
        @($Src.stages.name) | Should -Be @('Pilot', 'Last')
        # Tenants in the old stage 3 keep their progress; those in the removed stage 2 fall back.
        @($Src.stages.sourceStage) | Should -Be @(1, 3)
    }

    It 'inserts a whole stage straight after the chosen stage' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; mode = 'copy'; stage = 2; newStage = 0 })
        $R.StatusCode | Should -Be 200
        $Tgt = $script:Saved[0].Baseline
        @($Tgt.stages.name) | Should -Be @('One', 'Last', 'Two')
        # The inserted stage counts as reached only by tenants already in the stage it now precedes.
        @($Tgt.stages.sourceStage) | Should -Be @(1, 2, 2)
        $script:Saved.Count | Should -Be 1
    }

    It 'moves stage 1 as a new stage with no graduation conditions and empties it in the source' {
        $script:Baselines['src'].stages[0] = & $script:Stage 'Pilot' @((& $script:Config 'Branding'), (& $script:Config 'SafeLinks#abc12345'))
        $script:Baselines['src'].stages[0].conditionGroups = @()
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; stage = 0; newStage = 'end' })
        $R.StatusCode | Should -Be 200
        $R.Body.Results | Should -Match 'The new stage has no graduation conditions yet, so no tenant moves into it until you add one\. The baseline editor asks for one before Target can be saved again\.'
        $New = $script:Saved[0].Baseline.stages[2]
        $New.name | Should -Be 'Pilot'
        @($New.conditions).Count | Should -Be 0
        @($New.standards.standard) | Should -Be @('Branding', 'SafeLinks')
        $Src = $script:Saved[1].Baseline
        $Src.stages.Count | Should -Be 3
        $Src.stages[0].name | Should -Be 'Pilot'
        @($Src.stages[0].standards).Count | Should -Be 0
    }

    It 'gives a single standard its own named stage with no conditions at the end' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'DisableGuests'; sourceStage = 0; newStage = 'end' })
        $R.StatusCode | Should -Be 200
        $R.Body.Results | Should -Match 'no tenant moves into it until you add one'
        $Tgt = $script:Saved[0].Baseline
        @($Tgt.stages.name) | Should -Be @('One', 'Two', 'Disable Guests (from Source)')
        @($Tgt.stages[2].conditions).Count | Should -Be 0
        @($Tgt.stages[2].conditionGroups).Count | Should -Be 0
        @($Tgt.stages[2].standards.instance) | Should -Be @('DisableGuests')
        @($script:Saved[1].Baseline.stages[0].standards.instance) | Should -Be @('SafeLinks#abc12345')
    }

    It 'refuses a new stage with no conditions anywhere but the end' -ForEach @(
        @{ Case = 'a single standard'; Body = @{ sourceId = 'src'; targetId = 'tgt'; standard = 'DisableGuests'; sourceStage = 0; newStage = 0 } }
        @{ Case = 'a conditionless stage'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 0; newStage = 0 } }
    ) {
        $script:Baselines['src'].stages[0].conditionGroups = @()
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest $Body)
        $R.StatusCode | Should -Be 400
        $R.Body.Results | Should -Match 'can only go at the end'
        $script:Saved.Count | Should -Be 0
    }

    It 'names a new stage after the standard when the catalog has no label for it' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; mode = 'copy'; standard = 'Branding'; sourceStage = 2; newStage = 'end' })
        $R.StatusCode | Should -Be 200
        $script:Saved[0].Baseline.stages[2].name | Should -Be 'Branding (from Source)'
    }

    It 'refuses a new stage when the target already has 20 stages' {
        $script:Baselines['tgt'].stages = @(foreach ($i in 1..20) { & $script:Stage "S$i" @() })
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; stage = 1 })
        $R.StatusCode | Should -Be 400
        $R.Body.Results | Should -Match '20 stages'
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'refuses with 403 when either baseline is assigned outside the caller''s tenants' -ForEach @(
        @{ Blocked = 'contoso.com' }, @{ Blocked = 'fabrikam.com' }
    ) {
        $script:OutOfScope[$Blocked] = $Blocked
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 0 })
        $R.StatusCode | Should -Be 403
        $R.Body.Results | Should -Match $Blocked
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'returns 500 saying the standards were copied but not removed when the source save fails' {
        $script:SaveFailsFor = 'src'
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 0 })
        $R.StatusCode | Should -Be 500
        $R.Body.Results | Should -Match 'copied to stage 1 of Target, but could not be removed from Source'
        $script:Saved.Count | Should -Be 1
    }

    It 'returns 500 and writes nothing to the source when the target save fails' {
        $script:SaveFailsFor = 'tgt'
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 0 })
        $R.StatusCode | Should -Be 500
        $R.Body.Results | Should -Match 'Nothing was changed'
        $script:Saved.Count | Should -Be 0
    }

    It 'returns 404 for a missing baseline' {
        $R = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'src'; targetId = 'gone'; standard = 'Branding'; sourceStage = 2; targetStage = 0 })
        $R.StatusCode | Should -Be 404
        Should -Invoke New-CIPPBaseline -Times 0
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'the same baseline'; Body = @{ sourceId = 'src'; targetId = 'src'; stage = 1 } }
        @{ Case = 'a missing targetId'; Body = @{ sourceId = 'src'; stage = 1 } }
        @{ Case = 'an unknown mode'; Body = @{ sourceId = 'src'; targetId = 'tgt'; mode = 'swap'; stage = 1 } }
        @{ Case = 'a source stage out of range'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 5 } }
        @{ Case = 'an existing target stage out of range'; Body = @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 2 } }
        @{ Case = 'a new-stage position out of range'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 1; newStage = 2 } }
        @{ Case = 'a new stage before Stage 1'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 1; newStage = -1 } }
        @{ Case = 'an unknown new-stage position'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 1; newStage = 'middle' } }
        @{ Case = 'a standard not in the stage'; Body = @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Nope'; sourceStage = 0; targetStage = 0 } }
        @{ Case = 'a whole stage into an existing stage'; Body = @{ sourceId = 'src'; targetId = 'tgt'; stage = 1; targetStage = 0 } }
        @{ Case = 'both targetStage and newStage'; Body = @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2; targetStage = 0; newStage = 'end' } }
        @{ Case = 'a single standard with no placement'; Body = @{ sourceId = 'src'; targetId = 'tgt'; standard = 'Branding'; sourceStage = 2 } }
    ) {
        (Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest $Body)).StatusCode | Should -Be 400
        Should -Invoke New-CIPPBaseline -Times 0
    }
}

# The real read (Get-CIPPBaseline) and write (New-CIPPBaseline) over an in-memory table store: moving a
# standard to another baseline and back must leave both baselines' stored rows exactly as they were.
Describe 'Invoke-ExecMoveBaselineStandards round trip through the real baseline read and write' {
    BeforeAll {
        function Get-CippTable { param($tablename) @{ TableName = $tablename } }
        function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
        function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'cid-contoso'; defaultDomainName = 'contoso.com'; displayName = 'Contoso' } }
        function Get-TenantGroups { @([pscustomobject]@{ Id = 'grp-1'; Name = 'Pilot Group'; Members = @([pscustomobject]@{ defaultDomainName = 'contoso.com' }) }) }
        function Get-CIPPTemplateSourceUrl { param($Source, $SourcePath, $Repos) }
        function Get-CIPPBaselineWorkItems { param($TenantFilter) }
        function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail) }
        function Get-CIPPAzDataTableEntity { param($TableName, $Filter, [switch]$Force)
            foreach ($Row in @($script:Store[$TableName])) {
                $Match = $true
                foreach ($Clause in ($Filter -split ' and ')) {
                    if ($Clause -match "^(\w+) eq '(.*)'$" -and "$($Row.($Matches[1]))" -ne $Matches[2]) { $Match = $false }
                }
                if ($Match) { [pscustomobject]$Row }
            }
        }
        function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force)
            if (-not $script:Store[$TableName]) { $script:Store[$TableName] = [System.Collections.Generic.List[hashtable]]::new() }
            $List = $script:Store[$TableName]
            for ($i = $List.Count - 1; $i -ge 0; $i--) {
                if ($List[$i].PartitionKey -eq $Entity.PartitionKey -and $List[$i].RowKey -eq $Entity.RowKey) { $List.RemoveAt($i) }
            }
            $List.Add([hashtable]$Entity)
        }
        function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force)
            $List = $script:Store[$TableName]
            foreach ($Gone in @($Entity)) {
                for ($i = $List.Count - 1; $i -ge 0; $i--) {
                    if ($List[$i].PartitionKey -eq $Gone.PartitionKey -and $List[$i].RowKey -eq $Gone.RowKey) { $List.RemoveAt($i) }
                }
            }
        }
        $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/New-CIPPBaseline.ps1')
        . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaseline.ps1')
        . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
        . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')

        $script:Snapshot = {
            $Rows = foreach ($Table in @('BaselineRollouts', 'Baselines', 'BaselineRolloutState')) {
                foreach ($Row in @($script:Store[$Table])) {
                    $Copy = [ordered]@{ Table = $Table }
                    foreach ($Key in @($Row.Keys | Sort-Object)) { if ($Key -notin @('updatedAt', 'updatedBy')) { $Copy[$Key] = $Row[$Key] } }
                    ConvertTo-Json -Compress -Depth 20 -InputObject $Copy
                }
            }
            @($Rows | Sort-Object)
        }
    }

    BeforeEach {
        $script:Store = @{}
        Mock Get-CIPPBaselineDefinition { @([pscustomobject]@{ name = 'SafeLinks'; multiple = $true }) }
        Mock Get-CIPPBaselineOutOfScopeAssignment { }
        Mock Write-LogMessage { }
        $Manual = @{ type = 'manual' }
        $null = New-CIPPBaseline -User 'seed' -Baseline ([pscustomobject]@{
                GUID = 'base-a'; templateName = 'A'; description = 'first'; alertEmails = 'ops@example.com'; alertWebhookUrl = ''
                disableAlerts = $true; disableScheduledRuns = $false
                assignedTenants = @(@{ label = 'Contoso (contoso.com)'; value = 'contoso.com'; type = 'Tenant' })
                excludedTenants = @(@{ label = 'Pilot Group'; value = 'grp-1'; type = 'Group' })
                stages = @(
                    @{ name = 'Pilot'; logic = 'and'; conditions = @(); standards = @(
                            @{ standard = 'AuditLog'; instance = 'AuditLog'; variables = @{ days = 90 }; remediateEnabled = $true; alertEnabled = $false; alertOnRemediate = $true }
                            @{ standard = 'SafeLinks'; instance = 'SafeLinks#aaaa1111'; variables = @{ name = 'Policy' }; remediateEnabled = $false; alertEnabled = $true; alertOnRemediate = $false }
                        ) }
                    @{ name = 'Everyone'; logic = 'or'; conditions = @(@{ type = 'time'; days = 14; unit = 'days' }, $Manual); conditionGroups = @(@{ logic = 'and'; conditions = @($Manual) }); standards = @(
                            @{ standard = 'Branding'; instance = 'Branding'; variables = @{ color = '#fff' }; remediateEnabled = $true; alertEnabled = $true; alertOnRemediate = $false }
                        ) }
                )
            })
        $null = New-CIPPBaseline -User 'seed' -Baseline ([pscustomobject]@{
                GUID = 'base-b'; templateName = 'B'; description = ''; alertEmails = ''; alertWebhookUrl = 'https://hook.example.com'
                assignedTenants = @(@{ label = 'Pilot Group'; value = 'grp-1'; type = 'Group' }); excludedTenants = @()
                stages = @(@{ name = 'Only'; conditions = @(); standards = @(
                            @{ standard = 'DisableGuests'; instance = 'DisableGuests'; variables = @{}; remediateEnabled = $false; alertEnabled = $true; alertOnRemediate = $false }
                        ) })
            })
        $script:Store['BaselineRolloutState'] = [System.Collections.Generic.List[hashtable]]::new()
        $script:Store['BaselineRolloutState'].Add(@{ PartitionKey = 'base-a'; RowKey = 'cid-contoso'; currentStage = 2; enteredStageAt = 1000; firstDeployedAt = 900 })
        $script:Before = & $script:Snapshot
    }

    It 'leaves both baselines byte-for-byte unchanged after moving a standard there and back' {
        $Out = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-a'; targetId = 'base-b'; standard = 'Branding'; sourceStage = 1; targetStage = 0 })
        $Out.StatusCode | Should -Be 200
        (& $script:Snapshot) | Should -Not -Be $script:Before
        $Back = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-b'; targetId = 'base-a'; standard = 'Branding'; sourceStage = 0; targetStage = 1 })
        $Back.StatusCode | Should -Be 200

        $After = & $script:Snapshot
        $After.Count | Should -Be $script:Before.Count
        for ($i = 0; $i -lt $After.Count; $i++) { $After[$i] | Should -Be $script:Before[$i] }
    }

    It 'moves a tenant back to stage 1 when the stage it was in is moved away' {
        $Out = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-a'; targetId = 'base-b'; stage = 1 })
        $Out.StatusCode | Should -Be 200
        @((Get-CIPPBaseline -ID 'base-a').stages.name) | Should -Be @('Pilot')
        $script:Store['BaselineRolloutState'][0].currentStage | Should -Be 1
    }

    It 'keeps every tenant on its stage when a new stage is inserted mid-baseline' {
        $script:Store['BaselineRolloutState'].Add(@{ PartitionKey = 'base-a'; RowKey = 'cid-early'; currentStage = 1; enteredStageAt = 500; firstDeployedAt = 400 })
        # B gets a stage with conditions first, then it is inserted after A's Stage 1.
        $null = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-a'; targetId = 'base-b'; mode = 'copy'; stage = 1; newStage = 'end' })
        $Out = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-b'; targetId = 'base-a'; mode = 'copy'; stage = 1; newStage = 0 })
        $Out.StatusCode | Should -Be 200
        @((Get-CIPPBaseline -ID 'base-a').stages.name) | Should -Be @('Pilot', 'Everyone', 'Everyone')
        $States = @{}
        foreach ($Row in $script:Store['BaselineRolloutState']) { $States[$Row.RowKey] = $Row }
        # The tenant in 'Everyone' is still in 'Everyone', now stage 3, with its entry time kept.
        $States['cid-contoso'].currentStage | Should -Be 3
        $States['cid-contoso'].enteredStageAt | Should -Be 1000
        $States['cid-early'].currentStage | Should -Be 1
        $States['cid-early'].enteredStageAt | Should -Be 500
    }

    It 'keeps the untouched baseline unchanged on a copy' {
        $Out = Invoke-ExecMoveBaselineStandards -Request (& $script:NewRequest @{ sourceId = 'base-a'; targetId = 'base-b'; mode = 'copy'; stage = 1; newStage = 'end' })
        $Out.StatusCode | Should -Be 200
        $After = & $script:Snapshot
        @($After.Where({ $_ -match '"base-a"' })) | Should -Be @($script:Before.Where({ $_ -match '"base-a"' }))
        $B = Get-CIPPBaseline -ID 'base-b'
        @($B.stages.name) | Should -Be @('Only', 'Everyone')
        $B.stages[1].logic | Should -Be 'or'
        @($B.stages[1].conditions.type) | Should -Be @('time', 'manual')
        $B.stages[1].conditionGroups[0].conditions[0].type | Should -Be 'manual'
    }
}
