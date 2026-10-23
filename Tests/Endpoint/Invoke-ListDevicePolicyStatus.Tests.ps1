# Pester tests for Invoke-ListDevicePolicyStatus: input checks, the report body sent to Graph,
# and turning the report's Schema/Values table into rows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippBulkStatusCode.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListDevicePolicyStatus.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-PolicyStatusRequest {
        param([hashtable]$Query)
        $Merged = @{ tenantFilter = 'contoso.com' }
        foreach ($Key in $Query.Keys) { $Merged[$Key] = $Query[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListDevicePolicyStatus' }
            Headers = @{}
            Query   = [pscustomobject]$Merged
        }
    }

    $DeviceGuid = '3445a12c-aa76-4aec-bd60-e98728385900'
}

Describe 'Invoke-ListDevicePolicyStatus' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                TotalRowCount = 2
                Schema        = @(
                    [pscustomobject]@{ Column = 'PolicyName' }
                    [pscustomobject]@{ Column = 'ReportStatus' }
                )
                Values        = @(
                    , @('LAPS', 'Succeeded')
                    , @('Firewall', 'Error')
                )
            }
        }
    }

    It 'turns the report table into one row per policy' {
        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'configuration' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -HaveCount 2
        $Response.Body.Results[0].PolicyName | Should -Be 'LAPS'
        $Response.Body.Results[1].ReportStatus | Should -Be 'Error'
    }

    It 'asks the configuration report for every policy family on that device' {
        $null = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'configuration' }) -TriggerMetadata $null

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Sent = $body | ConvertFrom-Json
            $uri -like '*/reports/getConfigurationPoliciesReportForDevice' -and
            $Sent.filter -like "*IntuneDeviceId eq '$DeviceGuid'*" -and
            $Sent.filter -like '*DeviceManagementConfigurationPolicy*' -and
            $Sent.filter -like '*DeviceConfigurationAdmxPolicy*'
        }
    }

    It 'uses the compliance report for compliance' {
        $null = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'compliance' }) -TriggerMetadata $null

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            ($body | ConvertFrom-Json).filter -eq "(DeviceId eq '$DeviceGuid')" -and
            $uri -like '*/reports/getDevicePoliciesComplianceReport'
        }
    }

    It 'asks the enrollment report for its own columns without a PolicyName sort' {
        $null = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'enrollment' }) -TriggerMetadata $null

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Sent = $body | ConvertFrom-Json
            $uri -like '*/reports/getEnrollmentConfigurationPoliciesByDevice' -and
            $Sent.filter -eq "(DeviceId eq '$DeviceGuid')" -and
            ($Sent.select -join ',') -eq 'PolicyId,PolicyType,ProfileName' -and
            @($Sent.orderBy).Count -eq 0
        }
    }

    It 'rejects a device id that is not a GUID, so nothing reaches the OData filter' {
        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = "x') or (1 eq 1"; report = 'compliance' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'rejects an unknown report' {
        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'apps' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns the Graph error as a 500' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'compliance' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'Failed to load compliance policies'
    }

    It 'returns both reports in one response for report=all' {
        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'all' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.configuration | Should -HaveCount 2
        $Response.Body.Results.compliance | Should -HaveCount 2
        $Response.Body.Results.enrollment | Should -HaveCount 2
        $Response.Body.Results.errors.Count | Should -Be 0
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*getConfigurationPoliciesReportForDevice' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*getDevicePoliciesComplianceReport' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*getEnrollmentConfigurationPoliciesByDevice' }
    }

    It 'keeps the report that loaded when the other fails, as a 207' {
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*getDevicePoliciesComplianceReport' } -MockWith { throw 'Forbidden' }

        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'all' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 207
        $Response.Body.Results.configuration | Should -HaveCount 2
        $Response.Body.Results.compliance | Should -BeNullOrEmpty
        $Response.Body.Results.errors.compliance | Should -Match 'Failed to load compliance policies'
    }

    It 'returns 500 for report=all when every report fails' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

        $Response = Invoke-ListDevicePolicyStatus -Request (New-PolicyStatusRequest -Query @{ deviceId = $DeviceGuid; report = 'all' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results.errors.Count | Should -Be 3
    }
}
