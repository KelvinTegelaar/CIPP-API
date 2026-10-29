# Pester tests for the device a webhook alert carries to the PSA: the Entra device record the GUID
# mapper attached, or the sign-in device from DeviceProperties, and nothing for a user-only record.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Invoke-CIPPWebhookProcessing.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Get-Tenants { param([switch]$IncludeErrors, [switch]$IncludeAll) }
    function New-CIPPAlertTemplate { param($format, $data, $ActionResults, $CIPPURL, $AlertComment, $CustomSubject, $Tenant, $AuditLogLink) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $APIName, $SchemaSource, $InvokingCommand, $AffectedUser, $AffectedDevice, $PsaTicketPriority) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function ConvertTo-CIPPODataFilterValue { param([string]$Value, $Type) $Value -replace "'", "''" }

    . $FunctionPath

    function New-WebhookData {
        param([hashtable]$Extra = @{})
        $Data = [pscustomobject]@{
            Id                = 'rec-1'
            CreationTime      = '2026-10-29T10:00:00Z'
            CIPPAction        = (ConvertTo-Json -Compress -InputObject @(@{ label = 'Create PSA ticket'; value = 'generatePSA' }))
            CIPPLocationInfo  = $null
            AuditRecord       = '{}'
            CIPPCustomSubject = $null
            ClientIP          = '20.190.144.12'
            ObjectId          = $null
            UserId            = 'user1@contoso.com'
            Userkey           = $null
        }
        foreach ($Key in $Extra.Keys) { $Data | Add-Member -NotePropertyName $Key -NotePropertyValue $Extra[$Key] -Force }
        $Data
    }
}

Describe 'Invoke-CippWebhookProcessing - affected device' {
    BeforeEach {
        $script:WebhookTenantCache = @{}
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ Context = "ctx:$TableName" } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { @([pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'cid-contoso' }) }
        Mock -CommandName New-CIPPAlertTemplate -MockWith { [pscustomobject]@{ Title = 'alert'; ButtonUrl = 'https://example.invalid'; ButtonText = 'open'; htmlcontent = '<p>alert</p>' } }
        Mock -CommandName Send-CIPPAlert -MockWith { param($Type, $AffectedUser, $AffectedDevice) $script:Sent.Add([pscustomobject]@{ Type = $Type; AffectedUser = $AffectedUser; AffectedDevice = $AffectedDevice }) }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'carries the Entra device the GUID mapper attached' {
        $Data = New-WebhookData -Extra @{
            ObjectId     = '3c7b0d2e-0000-4000-8000-000000000001'
            CIPPObjectId = [pscustomobject]@{ id = '3c7b0d2e-0000-4000-8000-000000000001'; displayName = 'LAPTOP-01'; deviceId = 'aaaaaaaa-1111-4111-8111-111111111111' }
        }
        Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'
        $script:Sent.Count | Should -Be 1
        $script:Sent[0].AffectedDevice.EntraDeviceId | Should -Be 'aaaaaaaa-1111-4111-8111-111111111111'
        $script:Sent[0].AffectedDevice.DisplayName | Should -Be 'LAPTOP-01'
    }

    It 'ignores mapped groups and users and falls back to the sign-in device' {
        $Data = New-WebhookData -Extra @{
            CIPPTarget           = [pscustomobject]@{ id = 'g-1'; displayName = 'All Staff' }
            CIPPUserId           = 'user1@contoso.com'
            CIPPDeviceProperties = (ConvertTo-Json -Compress -InputObject @(@{ Name = 'Id'; Value = 'bbbbbbbb-2222-4222-8222-222222222222' }, @{ Name = 'DisplayName'; Value = 'DESKTOP-02' }, @{ Name = 'OS'; Value = 'Windows10' }))
        }
        Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'
        $script:Sent[0].AffectedDevice.EntraDeviceId | Should -Be 'bbbbbbbb-2222-4222-8222-222222222222'
        $script:Sent[0].AffectedDevice.DisplayName | Should -Be 'DESKTOP-02'
    }

    It 'sends no device for a record that names none' {
        $Data = New-WebhookData -Extra @{ CIPPUserId = 'user1@contoso.com' }
        Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'
        $script:Sent.Count | Should -Be 1
        $script:Sent[0].AffectedDevice | Should -BeNullOrEmpty
        $script:Sent[0].AffectedUser.UPN | Should -Be 'user1@contoso.com'
    }
}
