# Pester tests for Invoke-CIPPStandardReusableSettingsTemplate
# Validates licensing guard, remediation flows, alerting, and reporting

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Standards/Invoke-CIPPStandardReusableSettingsTemplate.ps1'

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $RequiredCapabilities) }
    function Get-CippTable { param($tablename) }
    function New-GraphGETRequest { param($uri, $tenantid) }
    function Get-CippAzDataTableEntity { param($Table, $Filter) }
    function Compare-CIPPIntuneObject { param($ReferenceObject, $DifferenceObject, $compareType) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Write-StandardsAlert { param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { param($FieldName, $FieldValue, $TenantFilter) }
    function Get-NormalizedError { param($Message) $Message }

    . $StandardPath
}

Describe 'Invoke-CIPPStandardReusableSettingsTemplate' {
    $tenant = 'contoso.onmicrosoft.com'

    BeforeEach {
        $script:compareFields = @()
        $script:alerts = @()
        $script:logs = @()
        $script:updateCalls = 0
        $script:createCalls = 0

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Get-CippTable -MockWith { @{ Table = 'templates' } }
        Mock -CommandName New-GraphGETRequest -MockWith { @() }
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            @([pscustomobject]@{
                    RowKey      = 'template-existing'
                    JSON        = '{"DisplayName":"Reusable A","RawJSON":"{\"displayName\":\"Reusable A\"}"}'
                    RawJSON     = '{"displayName":"Reusable A"}'
                    DisplayName = 'Reusable A'
                })
        }
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { $null }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            param($uri, $tenantid, $type, $body)
            if ($type -eq 'PUT') { $script:updateCalls++ } else { $script:createCalls++ }
        }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev)
            $script:logs += @{ Message = $message; Sev = $sev }
        }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object, $tenant, $standardName, $standardId)
            $script:alerts += @{ Message = $message; Object = $object; Standard = $standardName; Id = $standardId }
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $TenantFilter)
            $script:compareFields += @{ Field = $FieldName; Value = $FieldValue; Tenant = $TenantFilter }
        }
    }

    It 'sets compare fields and exits when license requirement fails' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }

        $settings = @(
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-one' } },
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-two' } }
        )

        $result = Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

        $result | Should -BeTrue
        $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-one'
        $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-two'
        Should -Invoke Get-CippAzDataTableEntity -Times 0
        Should -Invoke New-GraphGETRequest -Times 0
    }

    It 'creates missing reusable settings when remediate is enabled' {
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            @([pscustomobject]@{
                    RowKey      = 'template-create'
                    JSON        = '{"DisplayName":"Reusable Create","RawJSON":"{\"displayName\":\"Reusable Create\"}"}'
                    RawJSON     = '{"displayName":"Reusable Create"}'
                    DisplayName = 'Reusable Create'
                })
        }

        $settings = @(
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-create' }; remediate = $true; alert = $false; report = $false }
        )

        Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

        $createCalls | Should -Be 1
        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $type -eq 'POST' -and $uri -like '*reusablePolicySettings' } -Times 1
        $compareFields | Should -BeNullOrEmpty
    }

    It 'updates existing reusable settings when a mismatch is found' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @([pscustomobject]@{ id = 'existing-1'; displayName = 'Reusable A'; version = 1 })
        }
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { [pscustomobject]@{ Difference = 'changed' } }

        $settings = @(
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-existing' }; remediate = $true; alert = $false; report = $false }
        )

        Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

        $updateCalls | Should -Be 1
        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $type -eq 'PUT' -and $uri -like '*reusablePolicySettings/existing-1' } -Times 1
        Should -Invoke New-GraphPOSTRequest -ParameterFilter { $type -eq 'POST' } -Times 0
    }

    It 'writes standards alerts when alerting is enabled and drift exists' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @([pscustomobject]@{ id = 'existing-2'; displayName = 'Reusable Alert' })
        }
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { @{ Difference = 'drift' } }

        $settings = @(
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-existing' }; remediate = $false; alert = $true; report = $false }
        )

        Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

        $alerts | Should -HaveCount 1
        $alerts[0].Message | Should -Match 'Reusable setting Reusable A does not match'
        $alerts[0].Standard | Should -Be 'ReusableSettingsTemplate'
        $logs.Where({ $_.Message -like '*out of compliance*' }).Count | Should -Be 1
    }

    It 'logs compliance and reports true when no differences are found' {
        Mock -CommandName New-GraphGETRequest -MockWith {
            @([pscustomobject]@{ id = 'existing-3'; displayName = 'Reusable A' })
        }
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { $null }

        $settings = @(
            [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-existing' }; remediate = $false; alert = $true; report = $true }
        )

        Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

        $logs.Where({ $_.Message -like '*is compliant.*' }).Count | Should -Be 1
        $compareFields | Should -HaveCount 1
        $compareFields[0].Value | Should -BeTrue
        Should -Invoke -CommandName Write-StandardsAlert -Times 0
    }
}
