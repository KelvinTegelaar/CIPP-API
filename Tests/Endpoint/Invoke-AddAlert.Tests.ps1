# GHSA-w39h-8vjv-6qm5: condition values are validated on the way in, not only when the rule fires.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertTo-CIPPScriptBlockValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Test-CIPPConditionFilter.ps1')

    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $message, $sev, $LogData, $headers) }
    function Test-CippTenantInScope { param($Tenant) $true }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Alerts/Invoke-AddAlert.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Condition {
        param($Property = 'DisplayName', $Operator = 'eq', $Value)
        [pscustomobject]@{
            Property = [pscustomobject]@{ label = $Property; value = $Property }
            Operator = [pscustomobject]@{ label = 'equals'; value = $Operator }
            Input    = [pscustomobject]@{ value = $Value }
        }
    }

    function New-AddAlertRequest {
        param($Conditions)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAlert' }
            Headers = @{ 'x-ms-client-principal-name' = 'admin@contoso.com' }
            Body    = [pscustomobject]@{
                tenantFilter = @([pscustomobject]@{ label = 'Contoso'; value = 'contoso.com' })
                conditions   = @($Conditions)
                actions      = @([pscustomobject]@{ label = 'Webhook'; value = 'webhook' })
                logbook      = [pscustomobject]@{ label = 'Audit.AzureActiveDirectory'; value = 'Audit.AzureActiveDirectory' }
            }
        }
    }
}

Describe 'Invoke-AddAlert' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'stores a value with curly quotes as plain data' {
        $Payload = "a$([char]0x2019) -or (Write-Host injected) -or $([char]0x2019)b"

        $Response = Invoke-AddAlert -Request (New-AddAlertRequest -Conditions (New-Condition -Value $Payload))

        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { ($Entity.Conditions | ConvertFrom-Json).Input.value -eq $Payload }
    }

    It 'refuses a condition value the builder would refuse' {
        $Response = Invoke-AddAlert -Request (New-AddAlertRequest -Conditions (New-Condition -Value 'a$(whoami)'))

        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike 'Invalid value for condition on property: DisplayName*'
        Should -Not -Invoke Add-CIPPAzDataTableEntity
    }

    It 'refuses an operator that is not on the allowlist' {
        $Response = Invoke-AddAlert -Request (New-AddAlertRequest -Conditions (New-Condition -Operator 'join' -Value 'x'))

        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike 'Invalid operator*'
        Should -Not -Invoke Add-CIPPAzDataTableEntity
    }

    It 'stores a value with an apostrophe' {
        $Value = "O$([char]0x2019)Brien"

        $Response = Invoke-AddAlert -Request (New-AddAlertRequest -Conditions (New-Condition -Value $Value))

        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.Conditions -like "*$Value*" -and $Entity.PartitionKey -eq 'Webhookv2' }
    }

    It 'stores an array value and a condition that has no value yet' {
        $Conditions = @(
            (New-Condition -Property 'Operation' -Operator 'in' -Value @('Set-Mailbox', 'Add-MailboxPermission'))
            (New-Condition -Property 'CIPPGeoLocation' -Operator 'notin' -Value '')
        )

        $Response = Invoke-AddAlert -Request (New-AddAlertRequest -Conditions $Conditions)

        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
