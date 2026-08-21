# Pester tests for Invoke-CIPPStandardPhishProtection branding localization handling.
#
# An existing default localization can legitimately have no custom CSS. That state must not be
# mistaken for a missing localization: POSTing another default object produces ObjectConflict even
# though the subsequent customCSS PUT succeeds, leaving a misleading Error in the standards log.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardPhishProtection.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardPhishProtection.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter) }
    function Get-CIPPTable { [CmdletBinding()] param($TableName) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table) }
    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $Uri, $ContentType, $AsApp, $Type, $Body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = ($Exception | Out-String); RawError = ($Exception.ErrorDetails.Message ?? '') } }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }

    . $StandardPath
}

Describe 'Invoke-CIPPStandardPhishProtection localization handling' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Get-Tenants {
            [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111' }
        }
        Mock Get-CIPPTable { @{ Table = 'Config' } }
        Mock Get-CIPPAzDataTableEntity {
            @([pscustomobject]@{ RowKey = 'CIPPURL'; Value = 'cipp.example.com' })
        }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Add-CIPPBPAField { }
        Mock Set-CIPPStandardsCompareField { }
        Mock New-GraphPostRequest { }
    }

    It 'uses an existing default localization when custom CSS is empty' {
        $script:GraphGetCalls = 0
        Mock New-GraphGetRequest {
            $script:GraphGetCalls++
            if ($script:GraphGetCalls -eq 1) { return $null }
            return @([pscustomobject]@{ id = '0' })
        }

        Invoke-CIPPStandardPhishProtection -Tenant 'contoso.onmicrosoft.com' -Settings ([pscustomobject]@{
                remediate = $true
                alert     = $false
                report    = $false
            })

        Should -Invoke New-GraphPostRequest -Times 0 -ParameterFilter {
            $Type -eq 'POST' -and $Uri -like '*/branding/localizations/'
        }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'PUT' -and $Uri -like '*/branding/localizations/0/customCSS'
        }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter {
            $sev -eq 'Error' -and $message -like 'Failed to create default branding localization*'
        }
    }

    It 'creates the default localization when localization id zero is absent' {
        Mock New-GraphGetRequest { return @() }

        Invoke-CIPPStandardPhishProtection -Tenant 'contoso.onmicrosoft.com' -Settings ([pscustomobject]@{
                remediate = $true
                alert     = $false
                report    = $false
            })

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'POST' -and $Uri -like '*/branding/localizations/'
        }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'PUT' -and $Uri -like '*/branding/localizations/0/customCSS'
        }
    }

    It 'treats a create conflict as a recovered race when id zero appeared after the list' {
        Mock New-GraphGetRequest { @() }
        Mock New-GraphPostRequest {
            param($tenantid, $Uri, $ContentType, $AsApp, $Type, $Body, $AddedHeaders)
            if ($Type -eq 'POST') { throw 'Another object with the same value for property id already exists.' }
        }
        Mock Get-CippException {
            [pscustomobject]@{
                NormalizedError = 'Another object with the same value for property id already exists.'
                RawError        = '{"error":{"code":"Request_BadRequest","details":[{"code":"ObjectConflict","target":"id"}]}}'
            }
        }

        Invoke-CIPPStandardPhishProtection -Tenant 'contoso.onmicrosoft.com' -Settings ([pscustomobject]@{
                remediate = $true
                alert     = $false
                report    = $false
            })

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $sev -eq 'Info' -and $message -like 'Default branding localization already exists*'
        }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter {
            $sev -eq 'Error' -and $message -like 'Failed to create default branding localization*'
        }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'PUT' -and $Uri -like '*/branding/localizations/0/customCSS'
        }
    }

    It 'keeps unexpected default localization creation failures at error severity' {
        Mock New-GraphGetRequest { @() }
        Mock New-GraphPostRequest {
            param($tenantid, $Uri, $ContentType, $AsApp, $Type, $Body, $AddedHeaders)
            if ($Type -eq 'POST') { throw 'Authorization_RequestDenied' }
        }
        Mock Get-CippException {
            [pscustomobject]@{
                NormalizedError = 'Authorization_RequestDenied'
                RawError        = '{"error":{"code":"Authorization_RequestDenied"}}'
            }
        }

        Invoke-CIPPStandardPhishProtection -Tenant 'contoso.onmicrosoft.com' -Settings ([pscustomobject]@{
                remediate = $true
                alert     = $false
                report    = $false
            })

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $sev -eq 'Error' -and $message -like 'Failed to create default branding localization*Authorization_RequestDenied*'
        }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter {
            $sev -eq 'Info' -and $message -like 'Default branding localization already exists*'
        }
    }
}
