BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'cid-1'; defaultDomainName = 'contoso.com' } }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail) }
    function Get-CIPPBaselineDefinition { param($Name) @() }
    function Get-CIPPBaseline {
        param($ID)
        [pscustomobject]@{
            templateName = 'Staged'
            stages       = @(
                [pscustomobject]@{ name = 'S1'; standardsConfig = @([pscustomobject]@{ standard = 'A'; instance = 'A' }) }
                [pscustomobject]@{ name = 'S2'; standardsConfig = @([pscustomobject]@{ standard = 'B'; instance = 'B' }) }
                [pscustomobject]@{ name = 'S3'; standardsConfig = @([pscustomobject]@{ standard = 'C'; instance = 'C' }, [pscustomobject]@{ standard = 'A'; instance = 'A' }) }
            )
            tenantStates = @()
        }
    }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineStageStandards.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecBaselineStage.ps1')

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
}

Describe 'Moving a tenant back a baseline stage' {
    It 'clears the alignment rows only the later stages rolled out' {
        Mock Get-CIPPAzDataTableEntity {
            param($TableName, $Filter)
            if ($TableName -eq 'BaselineRolloutState') { return [pscustomobject]@{ RowKey = 'cid-1'; currentStage = 3 } }
            foreach ($Name in 'A', 'B', 'C') { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = $Name; StandardName = $Name } }
        }
        Mock Remove-CIPPAzDataTableEntity {}
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecBaselineStage' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; templateId = 'b1'; action = 'previous' } }

        $Response = Invoke-ExecBaselineStage -Request $Request

        $Response.StatusCode | Should -Be 200
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 'contoso.com' and TemplateId eq 'b1'" } -Times 1 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).StandardName -join ',' -eq 'C' }
    }
}

Describe 'Moving a tenant forward into a group-gated stage' {
    It 'refuses a tenant outside the group and leaves its stage alone' {
        Mock Get-CIPPBaseline {
            [pscustomobject]@{
                templateName = 'Staged'
                stages       = @([pscustomobject]@{ name = 'S1' }, [pscustomobject]@{ name = 'S2' })
                tenantStates = @([pscustomobject]@{ tenantFilter = 'contoso.com'; groupBlocked = $true })
            }
        }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'cid-1'; currentStage = 1 } }
        Mock Add-CIPPAzDataTableEntity {}
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecBaselineStage' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; templateId = 'b1' } }

        $Response = Invoke-ExecBaselineStage -Request $Request

        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*requires a tenant group*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
