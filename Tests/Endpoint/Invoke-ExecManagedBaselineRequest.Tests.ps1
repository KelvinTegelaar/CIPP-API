# Requesting a custom managed baseline, and refreshing, retrying or cancelling the request.
# Nothing that names the tenant may be typed, and nothing is sent or started when it is.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [string]$OperationType) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-Tenants { param($TenantFilter) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CIPPBaselineWorkItems { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) @{ RowKey = 'queue-1' } }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    function Update-CIPPManagedBaselineRequest { param($Row) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Test-CIPPManagedBaselineIdentifier.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecManagedBaselineRequest.ps1')

    $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@partner.example"}'))
    $script:NewRequest = {
        param($Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecManagedBaselineRequest' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]$Body }
    }
    $script:CreateBody = {
        param($Overrides = @{})
        $Body = @{
            Action       = 'Create'
            tenantFilter = [pscustomobject]@{ value = 'contoso.com'; label = 'Contoso Ltd' }
            industry     = [pscustomobject]@{ value = 'Healthcare'; label = 'Healthcare' }
            clientSize   = [pscustomobject]@{ value = '26-100'; label = '26-100' }
            wants        = 'Pass the cyber insurance questionnaire. Report only first.'
            exceptions   = 'Scanners still need SMTP basic authentication.'
            frameworks   = @([pscustomobject]@{ value = 'CIS'; label = 'CIS' })
            comments     = ''
        }
        foreach ($Key in $Overrides.Keys) { $Body[$Key] = $Overrides[$Key] }
        $Body
    }
    function New-Row {
        param($Status, $SubmittedAt)
        [pscustomobject]@{ PartitionKey = 'request'; RowKey = 'request-9'; TenantFilter = 'contoso.com'; Status = $Status; SubmittedAt = $SubmittedAt }
    }
}

Describe 'Invoke-ExecManagedBaselineRequest' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        $script:Started = $null
        Mock Write-LogMessage {}
        Mock Add-CIPPAzDataTableEntity { $script:Rows.Add($Entity) }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Get-CIPPAzDataTableEntity {}
        Mock Invoke-ManagedBaselinesRequest {}
        Mock Update-CIPPManagedBaselineRequest { 'Completed - ready to confirm' }
        Mock Start-CIPPOrchestrator { $script:Started = $InputObject }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com'; displayName = 'Contoso Ltd'; customerId = '9f2c7b1e-4a6d-4c3f-8b9a-5e1d2f7c0a44'; initialDomainName = 'contoso.onmicrosoft.com' } }
        Mock New-CIPPDbRequest { [pscustomobject]@{ id = 'contoso.nl' } }
        Mock Get-CIPPBaselineWorkItems { [pscustomobject]@{ BaseName = 'SmartLockout' } }
        Mock Get-CIPPBaselineDefinition {
            [pscustomobject]@{ name = 'SmartLockout' }
            [pscustomobject]@{ name = 'OauthConsent' }
            [pscustomobject]@{ name = 'NotReady'; disabled = $true }
            [pscustomobject]@{ name = 'CAPackage'; package = [pscustomobject]@{ templatePartition = 'CATemplate' } }
            [pscustomobject]@{ name = 'ManualTask'; manual = [pscustomobject]@{ name = 'Do it' } }
            [pscustomobject]@{ name = 'OptedOut'; managedCollection = $false }
        }
    }

    Context 'Create' {
        It 'stores the request and starts one compare per usable standard, with the send step after them' {
            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody))

            $Response.StatusCode | Should -Be 200
            $Stored = $script:Rows[0]
            $Stored.Status | Should -Be 'Waiting on data collection'
            $Stored.TenantFilter | Should -Be 'contoso.com'
            $Stored.Industry | Should -Be 'Healthcare'
            $Stored.Wants | Should -BeLike 'Pass the cyber insurance*'
            $Stored.Frameworks | Should -Be '["CIS"]'
            $Stored.CreatedBy | Should -Be 'admin@partner.example'

            $script:Started.Batch.Count | Should -Be 2
            $script:Started.Batch.Standard | Should -Be @('SmartLockout', 'OauthConsent')
            $script:Started.Batch.FunctionName | Select-Object -Unique | Should -Be 'CIPPManagedBaselineCollect'
            $script:Started.Batch.InBaseline | Should -Be @($true, $false)
            $script:Started.Batch[0].RequestId | Should -Be $Stored.RowKey
            $script:Started.PostExecution.FunctionName | Should -Be 'CIPPManagedBaselineSubmit'
            $script:Started.PostExecution.Parameters.RequestId | Should -Be $Stored.RowKey
            $script:Rows[-1].Total | Should -Be 2
        }

        It 'leaves out a standard whose definition opts out of collection' {
            $null = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody))

            $script:Started.Batch.Standard | Should -Not -Contain 'OptedOut'
            $script:Rows[-1].Total | Should -Be 2
        }

        It 'hands the compares everything that names the tenant, so it can be removed from the snapshot' {
            $null = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody))

            $Identifiers = $script:Started.Batch[0].TenantIdentifiers
            foreach ($Expected in 'Contoso Ltd', 'contoso.com', 'contoso.onmicrosoft.com', 'contoso', 'contoso.nl', '9f2c7b1e-4a6d-4c3f-8b9a-5e1d2f7c0a44') {
                $Identifiers | Should -Contain $Expected
            }
        }

        It 'refuses <Label> that holds <Case>, and stores and starts nothing' -ForEach @(
            @{ Label = 'What you expect'; Case = 'an email address'; Override = @{ wants = 'Notify ceo@fabrikam.example of every change' } }
            @{ Label = 'Exceptions'; Case = 'the tenant''s own domain'; Override = @{ exceptions = 'Leave mail.contoso.nl forwarding alone' } }
            @{ Label = 'Industry'; Case = 'the tenant''s name'; Override = @{ industry = 'Contoso Ltd healthcare' } }
            @{ Label = 'Comments'; Case = 'an IP address'; Override = @{ comments = 'Office is at 203.0.113.5' } }
            @{ Label = 'Frameworks'; Case = 'an ID'; Override = @{ frameworks = @('0b1e7c4a-9f3d-4e6a-8c2b-2d7f1a9e3c40') } }
        ) {
            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody $Override))

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike "$Label contains *Describe it instead of naming it*"
            $script:Rows.Count | Should -Be 0
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        }

        It 'allows the domain of a product the client uses' {
            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody @{ wants = 'Single sign-on with salesforce.com must keep working' }))

            $Response.StatusCode | Should -Be 200
        }

        It 'refuses without <Field>' -ForEach @(
            @{ Field = 'what you expect'; Override = @{ wants = '  ' }; Message = 'What you expect is required.' }
            @{ Field = 'an industry'; Override = @{ industry = '' }; Message = 'Industry is required.' }
            @{ Field = 'a single tenant'; Override = @{ tenantFilter = 'AllTenants' }; Message = 'Choose the tenant to snapshot.' }
        ) {
            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody $Override))

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Be $Message
            $script:Rows.Count | Should -Be 0
        }

        It 'leaves the request failed when the compares cannot be started' {
            Mock Start-CIPPOrchestrator { throw 'queue unavailable' }

            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest (& $script:CreateBody))

            $Response.StatusCode | Should -Be 500
            $script:Rows[-1].Status | Should -Be 'Failed'
            $script:Rows[-1].Error | Should -BeLike '*queue unavailable*'
        }
    }

    Context 'Refresh, Retry and Cancel' {
        It 'asks CyberDrain about a request that was sent' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }

            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Refresh'; requestId = 'request-9' })

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -BeLike "*'Completed - ready to confirm'*"
            Should -Invoke Update-CIPPManagedBaselineRequest -Times 1 -Exactly
        }

        It 'does not ask CyberDrain about a request that has not been sent yet' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on data collection' } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }

            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Refresh'; requestId = 'request-9' })

            $Response.StatusCode | Should -Be 200
            Should -Invoke Update-CIPPManagedBaselineRequest -Times 0 -Exactly
        }

        It 'starts a failed request again from a clean collection' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Failed' } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'request-9'; RowKey = 'SmartLockout' } } -ParameterFilter { $Context -eq 'ManagedBaselineCollection' }

            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Retry'; requestId = 'request-9' })

            $Response.StatusCode | Should -Be 200
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Context -eq 'ManagedBaselineCollection' }
            $script:Rows[0].Status | Should -Be 'Waiting on data collection'
            $script:Started.Batch.Count | Should -Be 2
        }

        It 'only retries a request that failed' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }

            (Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Retry'; requestId = 'request-9' })).StatusCode | Should -Be 400
            Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        }

        It 'cancels a sent request at CyberDrain and removes it here' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }

            $Response = Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Cancel'; requestId = 'request-9' })

            $Response.StatusCode | Should -Be 200
            Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'requests/request-9' -and $Method -eq 'DELETE' }
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
        }

        It 'still removes the request here when CyberDrain cannot be told' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
            Mock Invoke-ManagedBaselinesRequest { throw 'service is down' }

            (Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Cancel'; requestId = 'request-9' })).StatusCode | Should -Be 200
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
        }

        It 'does not cancel a request that is implemented' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Implemented' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }

            (Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Cancel'; requestId = 'request-9' })).StatusCode | Should -Be 400
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'answers not found for a request whose tenant the caller cannot access' {
            Mock Get-CIPPAzDataTableEntity { New-Row 'Waiting on CyberDrain' 100 } -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
            Mock Select-CippAllowedTenantData {}

            (Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Cancel'; requestId = 'request-9' })).StatusCode | Should -Be 404
            Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    It 'refuses an action it does not know' {
        (Invoke-ExecManagedBaselineRequest -Request (& $script:NewRequest @{ Action = 'Delete' })).StatusCode | Should -Be 400
    }
}
