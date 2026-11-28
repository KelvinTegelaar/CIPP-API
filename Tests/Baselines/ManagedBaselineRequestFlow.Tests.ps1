# A custom managed baseline request after its form is submitted: what is sent, sending it,
# asking CyberDrain where it stands, and saving the baseline CyberDrain delivered.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [string]$OperationType) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Query, $Body) }
    function Import-CIPPManagedBaseline { param($Package, $Baseline, $Kind, $RequestId, $User, [string[]]$TemplateIds) }
    foreach ($Name in 'Get-CIPPManagedBaselineRequestBody', 'Update-CIPPManagedBaselineRequest', 'Complete-CIPPManagedBaselineRequest') {
        . (Join-Path $BackendRoot "Modules/CIPPCore/Public/Baselines/$Name.ps1")
    }
    . (Join-Path $BackendRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Baselines/Push-CIPPManagedBaselineSubmit.ps1')

    function New-Row {
        param($Status = 'Waiting on data collection', $SubmittedAt, [bool]$ConfirmPending = $false)
        [pscustomobject]@{
            PartitionKey = 'request'; RowKey = 'request-9'; TenantFilter = 'contoso.com'
            Industry = 'Healthcare'; ClientSize = '26-100'
            Wants = 'Pass the insurance questionnaire'; Exceptions = 'Scanners need SMTP'
            Frameworks = '["CIS","NIS2"]'; Comments = ''; Status = $Status
            SubmittedAt = $SubmittedAt; ConfirmPending = $ConfirmPending
        }
    }
    $script:Collected = @(
        [pscustomobject]@{ PartitionKey = 'request-9'; RowKey = 'SmartLockout'; Status = 'Drift'; InBaseline = $true; Current = '{"lockoutThreshold":5}'; DiffersOn = '["lockoutThreshold"]' }
        [pscustomobject]@{ PartitionKey = 'request-9'; RowKey = 'ConditionalAccessTemplate'; Status = 'Needs a choice'; InBaseline = $false; Current = ''; DiffersOn = '[]' }
    )
    $script:Package = [pscustomobject]@{ id = 'custom-1'; version = 2; Baseline = [pscustomobject]@{ templateName = 'Custom baseline' }; Templates = @() }
}

Describe 'Get-CIPPManagedBaselineRequestBody' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { if ($Context -eq 'ManagedBaselineCollection') { $script:Collected } }
    }

    It 'carries what was typed and one entry per standard' {
        $Body = Get-CIPPManagedBaselineRequestBody -Row (New-Row)

        $Body.requestId | Should -Be 'request-9'
        $Body.Keys | Should -Not -Contain 'market'
        $Body.wants | Should -Be 'Pass the insurance questionnaire'
        $Body.exceptions | Should -Be 'Scanners need SMTP'
        $Body.frameworks | Should -Be @('CIS', 'NIS2')
        $Body.standards.Count | Should -Be 2
        $Lockout = $Body.standards | Where-Object { $_.standard -eq 'SmartLockout' }
        $Lockout.status | Should -Be 'Drift'
        $Lockout.inBaseline | Should -BeTrue
        $Lockout.current.lockoutThreshold | Should -Be 5
        $Lockout.differsOn | Should -Be @('lockoutThreshold')
    }

    It 'never carries the tenant' {
        $Json = ConvertTo-Json -Depth 20 -Compress -InputObject (Get-CIPPManagedBaselineRequestBody -Row (New-Row))

        $Json | Should -Not -Match 'contoso'
        $Json | Should -Not -Match 'tenant'
    }
}

Describe 'Push-CIPPManagedBaselineSubmit' {
    BeforeEach {
        $script:Changes = $null
        Mock Write-LogMessage {}
        Mock Add-CIPPAzDataTableEntity { $script:Changes = $Entity }
        Mock Get-CIPPAzDataTableEntity { if ($Context -eq 'ManagedBaselineCollection') { $script:Collected } else { New-Row } }
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ requestId = 'request-9'; status = 'submitted' } }
    }

    It 'sends the snapshot and moves the request to Waiting on CyberDrain' {
        Push-CIPPManagedBaselineSubmit -Item @{ Parameters = @{ RequestId = 'request-9' } }

        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'PartnerRequest' -and $Method -eq 'POST' -and $Body.standards.Count -eq 2 }
        $script:Changes.Status | Should -Be 'Waiting on CyberDrain'
        $script:Changes.SubmittedAt | Should -BeGreaterThan 0
    }

    It 'leaves the request failed with the reason when sending fails' {
        Mock Invoke-ManagedBaselinesRequest { throw 'CyberDrain rejected the API key.' }

        Push-CIPPManagedBaselineSubmit -Item @{ Parameters = @{ RequestId = 'request-9' } }

        $script:Changes.Status | Should -Be 'Failed'
        $script:Changes.Error | Should -BeLike '*rejected the API key*'
        $script:Changes.ContainsKey('SubmittedAt') | Should -BeFalse
    }

    It 'sends nothing for a request that was cancelled meanwhile' {
        Mock Get-CIPPAzDataTableEntity {}

        Push-CIPPManagedBaselineSubmit -Item @{ Parameters = @{ RequestId = 'request-9' } }

        Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}

Describe 'Update-CIPPManagedBaselineRequest' {
    BeforeEach {
        $script:Changes = $null
        Mock Write-LogMessage {}
        Mock Add-CIPPAzDataTableEntity { $script:Changes = $Entity }
    }

    It 'moves a request to ready when CyberDrain says so and keeps the notes and version' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; version = 2; engineerNotes = 'Two stages, report only first.' } }

        Update-CIPPManagedBaselineRequest -Row (New-Row 'Waiting on CyberDrain' 100) | Should -Be 'Completed - ready to confirm'

        $script:Changes.Status | Should -Be 'Completed - ready to confirm'
        $script:Changes.RemoteVersion | Should -Be '2'
        $script:Changes.EngineerNotes | Should -Be 'Two stages, report only first.'
    }

    It 'keeps waiting while CyberDrain is still working on it' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'in_progress' } }

        Update-CIPPManagedBaselineRequest -Row (New-Row 'Waiting on CyberDrain' 100) | Should -Be 'Waiting on CyberDrain'
    }

    It 'fails a request CyberDrain cancelled' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'cancelled' } }

        Update-CIPPManagedBaselineRequest -Row (New-Row 'Waiting on CyberDrain' 100) | Should -Be 'Failed'
        $script:Changes.Error | Should -BeLike '*cancelled*'
    }

    It 'does not ask about a request that was never sent' {
        Mock Invoke-ManagedBaselinesRequest {}

        Update-CIPPManagedBaselineRequest -Row (New-Row 'Failed') | Should -Be 'Failed'
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
    }

    It 'repeats a confirm call that failed earlier' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; version = 2 } }

        $null = Update-CIPPManagedBaselineRequest -Row (New-Row 'Implemented' 100 $true)

        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'PartnerRequestConfirm' -and $Body.requestId -eq 'request-9' -and $Method -eq 'POST' }
        $script:Changes.ConfirmPending | Should -BeFalse
        $script:Changes.Status | Should -Be 'Implemented'
    }
}

Describe 'Complete-CIPPManagedBaselineRequest' {
    BeforeEach {
        $script:Changes = $null
        $script:Payload = [pscustomobject]@{ templateName = 'Contoso baseline' }
        Mock Write-LogMessage {}
        Mock Add-CIPPAzDataTableEntity { $script:Changes = $Entity }
        Mock Get-CIPPAzDataTableEntity { New-Row 'Completed - ready to confirm' 100 }
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; version = 2; package = $script:Package } }
        Mock Import-CIPPManagedBaseline { @{ GUID = 'baseline-1'; DeltaCount = 4; Templates = 0; Failures = @() } }
    }

    It 'saves what the operator reviewed as a managed baseline and marks the request implemented' {
        $Saved = Complete-CIPPManagedBaselineRequest -RequestId 'request-9' -Baseline $script:Payload -Version '2' -User 'admin@partner.example'

        $Saved.GUID | Should -Be 'baseline-1'
        Should -Invoke Import-CIPPManagedBaseline -Times 1 -Exactly -ParameterFilter {
            $Kind -eq 'custom' -and $RequestId -eq 'request-9' -and $Baseline.templateName -eq 'Contoso baseline' -and $Package.id -eq 'custom-1'
        }
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'PartnerRequestConfirm' -and $Body.requestId -eq 'request-9' }
        $script:Changes.Status | Should -Be 'Implemented'
        $script:Changes.BaselineGUID | Should -Be 'baseline-1'
        $script:Changes.ConfirmPending | Should -BeFalse
    }

    It 'refuses when CyberDrain changed the delivery after the editor loaded it, and saves nothing' {
        { Complete-CIPPManagedBaselineRequest -RequestId 'request-9' -Baseline $script:Payload -Version '1' } |
            Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*while you were reviewing*'

        Should -Invoke Import-CIPPManagedBaseline -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'still saves when telling CyberDrain fails, and leaves the call to be repeated' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'ready'; version = 2; package = $script:Package } } -ParameterFilter { $Path -eq 'PartnerRequest' -and $Query.requestId -eq 'request-9' }
        Mock Invoke-ManagedBaselinesRequest { throw 'service is down' } -ParameterFilter { $Path -eq 'PartnerRequestConfirm' -and $Body.requestId -eq 'request-9' }

        $Saved = Complete-CIPPManagedBaselineRequest -RequestId 'request-9' -Baseline $script:Payload -Version '2'

        $Saved.GUID | Should -Be 'baseline-1'
        $script:Changes.Status | Should -Be 'Implemented'
        $script:Changes.ConfirmPending | Should -BeTrue
    }

    It 'refuses a request CyberDrain has not delivered yet' {
        Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 }

        { Complete-CIPPManagedBaselineRequest -RequestId 'request-9' -Baseline $script:Payload } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
    }

    It 'answers not found for a request the caller cannot see' {
        Mock Get-CIPPAzDataTableEntity {}

        { Complete-CIPPManagedBaselineRequest -RequestId 'request-9' -Baseline $script:Payload } |
            Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }
}
