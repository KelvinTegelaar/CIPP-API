# Pester tests for the Invoke-CIPPStandardUserSubmissions verdict.
#
# Two ways the verdict came out compliant when it was not:
#   - a failed Exchange read left the policy state empty, which the disable branch reads as
#     "no policy exists, so reporting is off";
#   - the report address fields are lists, and -eq against a list filters it instead of
#     comparing, so an extra address next to the configured one still passed.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardUserSubmissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardUserSubmissions.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardUserSubmissions verdict' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'reports nothing when the Exchange read fails, instead of grading disable as compliant' {
        Mock New-ExoRequest { throw 'Exchange is unavailable' }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{ state = 'disable'; alert = $true; report = $true; remediate = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like '*already configured*' -or $message -like '*properly configured*' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }

    It 'alerts when a report address list holds an extra address next to the configured one' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-ReportSubmissionPolicy') {
                [pscustomobject]@{
                    EnableReportToMicrosoft          = $true
                    ReportJunkToCustomizedAddress    = $true
                    ReportNotJunkToCustomizedAddress = $true
                    ReportPhishToCustomizedAddress   = $true
                    ReportJunkAddresses              = @('someone-else@contoso.com', 'security@contoso.com')
                    ReportNotJunkAddresses           = 'security@contoso.com'
                    ReportPhishAddresses             = 'security@contoso.com'
                }
            } elseif ($cmdlet -eq 'Get-ReportSubmissionRule') {
                [pscustomobject]@{ State = 'Enabled'; SentTo = 'security@contoso.com' }
            }
        }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{ state = 'enable'; email = 'security@contoso.com'; alert = $true }

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly
    }

    It 'stays compliant when every address field holds exactly the configured address' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-ReportSubmissionPolicy') {
                [pscustomobject]@{
                    EnableReportToMicrosoft          = $true
                    ReportJunkToCustomizedAddress    = $true
                    ReportNotJunkToCustomizedAddress = $true
                    ReportPhishToCustomizedAddress   = $true
                    ReportJunkAddresses              = @('security@contoso.com')
                    ReportNotJunkAddresses           = @('security@contoso.com')
                    ReportPhishAddresses             = @('security@contoso.com')
                }
            } elseif ($cmdlet -eq 'Get-ReportSubmissionRule') {
                [pscustomobject]@{ State = 'Enabled'; SentTo = @('security@contoso.com') }
            }
        }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{ state = 'enable'; email = 'security@contoso.com'; alert = $true }

        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
    }
}
