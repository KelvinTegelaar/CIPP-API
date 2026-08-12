# Pester tests for Invoke-CIPPStandardReusableSettingsTemplate
# Validates licensing guard, remediation flows, alerting, and reporting

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardReusableSettingsTemplate.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardReusableSettingsTemplate.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict
    # parameter binding makes signature drift in the standard fail loudly here instead
    # of silently landing in $args and leaving the captured value $null.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $RequiredCapabilities, $Preset, [switch]$SkipLog) }
    function Get-CippTable { param($tablename) }
    function New-GraphGETRequest { param($uri, $tenantid) }
    function Get-CippAzDataTableEntity { param($Table, $Filter) }
    function Compare-CIPPIntuneObject { param($ReferenceObject, $DifferenceObject, $compareType) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Write-StandardsAlert { param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, [bool]$LicenseAvailable = $true, [array]$BulkFields) }
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
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $LicenseAvailable)
            $script:compareFields += @{
                Field            = $FieldName
                Value            = $FieldValue
                Current          = $CurrentValue
                Expected         = $ExpectedValue
                Tenant           = $TenantFilter
                LicenseAvailable = $LicenseAvailable
            }
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
        # The report branch reports through CurrentValue/ExpectedValue, not the legacy FieldValue.
        $compareFields[0].Current.isCompliant | Should -BeTrue
        $compareFields[0].Current.displayName | Should -Be 'Reusable A'
        $compareFields[0].Expected.isCompliant | Should -BeTrue
        Should -Invoke -CommandName Write-StandardsAlert -Times 0
    }

    # Alignment emits a key for every selected id. A key with no compare row reports NOT FOUND, and
    # stays in ValidDriftKeys, which the drift prune skips - so it could never be cleared.
    Context 'compare rows always cover every selected template' {
        It 'writes a compare row for a template whose row no longer exists' {
            Mock -CommandName Get-CippAzDataTableEntity -MockWith { @() }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-deleted' }; remediate = $false; alert = $false; report = $true }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-deleted'
            ($compareFields | Where-Object Field -EQ 'standards.ReusableSettingsTemplate.template-deleted').Current.isCompliant |
                Should -BeFalse
        }

        It 'writes a compare row for a template whose stored JSON is empty' {
            Mock -CommandName Get-CippAzDataTableEntity -MockWith {
                @([pscustomobject]@{ RowKey = 'template-empty'; JSON = ''; DisplayName = 'Empty' })
            }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-empty' }; remediate = $false; alert = $false; report = $true }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-empty'
        }

        It 'covers the resolvable ids when only some of a selection resolve' {
            # The unresolved id used to produce nothing at all, which is harder to spot.
            Mock -CommandName Get-CippAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        RowKey      = 'template-good'
                        JSON        = '{"DisplayName":"Reusable Good","RawJSON":"{\"displayName\":\"Reusable Good\"}"}'
                        DisplayName = 'Reusable Good'
                    })
            }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = @('template-good', 'template-missing') }; remediate = $false; alert = $false; report = $true }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-good'
            $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.template-missing'
        }

        It 'never pushes an empty body for an unresolved template' {
            Mock -CommandName Get-CippAzDataTableEntity -MockWith { @() }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'template-deleted' }; remediate = $true; alert = $false; report = $false }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            Should -Invoke -CommandName New-GraphPOSTRequest -Times 0
        }
    }

    Context 'compare key matches the id the picker sent' {
        It 'keys off TemplateList.value, not the GUID inside the stored JSON' {
            # The JSON blob's GUID matches the RowKey for CIPP-created templates but not for
            # imported rows, where it wrote the row under a key nobody reads.
            Mock -CommandName Get-CippAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        RowKey      = 'row-key-id'
                        JSON        = '{"DisplayName":"Reusable A","GUID":"a-different-guid","RawJSON":"{\"displayName\":\"Reusable A\"}"}'
                        DisplayName = 'Reusable A'
                    })
            }
            Mock -CommandName New-GraphGETRequest -MockWith {
                @([pscustomobject]@{ id = 'existing-9'; displayName = 'Reusable A' })
            }
            Mock -CommandName Compare-CIPPIntuneObject -MockWith { $null }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'row-key-id' }; remediate = $false; alert = $false; report = $true }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            $compareFields.Field | Should -Contain 'standards.ReusableSettingsTemplate.row-key-id'
            $compareFields.Field | Should -Not -Contain 'standards.ReusableSettingsTemplate.a-different-guid'
        }

        It 'raises its alert against the picker id too' {
            Mock -CommandName Get-CippAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        RowKey      = 'row-key-id'
                        JSON        = '{"DisplayName":"Reusable A","GUID":"a-different-guid","RawJSON":"{\"displayName\":\"Reusable A\"}"}'
                        DisplayName = 'Reusable A'
                    })
            }
            Mock -CommandName New-GraphGETRequest -MockWith {
                @([pscustomobject]@{ id = 'existing-9'; displayName = 'Reusable A' })
            }
            # [pscustomobject] to match what Compare-CIPPIntuneObject really returns.
            Mock -CommandName Compare-CIPPIntuneObject -MockWith { [pscustomobject]@{ Difference = 'drift' } }

            $settings = @(
                [pscustomobject]@{ TemplateList = [pscustomobject]@{ value = 'row-key-id' }; remediate = $false; alert = $true; report = $false }
            )

            Invoke-CIPPStandardReusableSettingsTemplate -Tenant $tenant -Settings $settings

            $alerts | Should -HaveCount 1
            $alerts[0].Id | Should -BeExactly 'row-key-id'
        }
    }
}
