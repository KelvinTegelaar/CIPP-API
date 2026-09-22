# Pester tests for Invoke-ExecAcknowledgeAlert
#
# Acknowledging marks an Open AlertLifecycle row as Acknowledged with who did it, when and an
# optional note; un-acknowledging returns it to Open. Any other transition is refused, a
# missing row is a 404, and restricted callers are held to their tenant scope.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAcknowledgeAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecAcknowledgeAlert.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList, [switch]$GroupList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-AckRequest {
        param($Action = 'Acknowledge', $Note = '', $TenantFilter = 'contoso.onmicrosoft.com', $RowKey = 'Get-CIPPAlertSomething-hash123')
        $Principal = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = 'ops@contoso.com' } | ConvertTo-Json -Compress)))
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAcknowledgeAlert' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]@{ TenantFilter = $TenantFilter; RowKey = $RowKey; Action = $Action; Note = $Note }
            Query   = [pscustomobject]@{ }
        }
    }

    function New-Row {
        param($Status = 'Open')
        [pscustomobject]@{
            PartitionKey    = 'contoso.onmicrosoft.com'
            RowKey          = 'Get-CIPPAlertSomething-hash123'
            CmdletName      = 'Get-CIPPAlertSomething'
            Tenant          = 'contoso.onmicrosoft.com'
            ContentHash     = 'hash123'
            ContentPreview  = 'user@contoso.com'
            Status          = $Status
            AcknowledgedBy  = if ($Status -eq 'Acknowledged') { 'someone@contoso.com' } else { '' }
            AcknowledgedAt  = ''
            AcknowledgeNote = ''
            ETag            = 'W/"1"'
            Timestamp       = [datetimeoffset]::UtcNow
        }
    }
}

Describe 'Invoke-ExecAcknowledgeAlert' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertLifecycle' } }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row -Status 'Open' }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity }
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.onmicrosoft.com' }
        }
    }

    It 'acknowledges an open alert with the caller and note' {
        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -Note 'ticket 42') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Status | Should -Be 'Acknowledged'
        $script:Written.Status | Should -Be 'Acknowledged'
        $script:Written.AcknowledgedBy | Should -Be 'ops@contoso.com'
        $script:Written.AcknowledgedAt | Should -Not -BeNullOrEmpty
        $script:Written.AcknowledgeNote | Should -Be 'ticket 42'
        $script:Written.Keys | Should -Not -Contain 'ETag'
        $script:Written.ContentPreview | Should -Be 'user@contoso.com'
    }

    It 'returns an acknowledged alert to open' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row -Status 'Acknowledged' }

        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -Action 'Unacknowledge') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Written.Status | Should -Be 'Open'
        $script:Written.AcknowledgedBy | Should -Be ''
    }

    It 'refuses to acknowledge anything that is not open' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row -Status 'Snoozed' }

        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'refuses to un-acknowledge an alert that is not acknowledged' {
        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -Action 'Unacknowledge') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'rejects unknown actions and missing keys' {
        (Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -Action 'Delete') -TriggerMetadata $null).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        (Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -RowKey '') -TriggerMetadata $null).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns 404 when the row is gone' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }

        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'refuses a restricted caller naming a tenant outside their scope' {
        Mock -CommandName Test-CIPPAccess -MockWith { @('tenant-guid') }
        Mock -CommandName Get-Tenants -MockWith { }

        $Response = Invoke-ExecAcknowledgeAlert -Request (New-AckRequest -TenantFilter 'other.onmicrosoft.com') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
