# Pester tests for the Invoke-CIPPStandardEnableAppConsentRequests report grade.
#
# The report grades that each configured reviewer role and user is PRESENT among the tenant's reviewers.
# It used to compare the reviewer count, which never converged: remediation deliberately keeps reviewers
# added by hand, so any extra reviewer left the tenant permanently non-compliant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardEnableAppConsentRequests.ps1'

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $uri, $type, $body, $AsApp, $ContentType) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:GA = '62e90394-69f5-4237-9190-012177145e10'
    $script:SecAdmin = '194ae4cb-b126-40b2-bd5b-6091b380977d'

    function New-RoleReviewer { param($RoleId) [PSCustomObject]@{ query = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$RoleId'"; queryType = 'MicrosoftGraph'; queryRoot = $null } }
    function New-UserReviewer { param($Id) [PSCustomObject]@{ query = "/v1.0/users/$Id"; queryType = 'MicrosoftGraph'; queryRoot = $null } }

    function Set-Policy {
        param($Reviewers)
        $script:Policy = [PSCustomObject]@{ isEnabled = $true; reviewers = @($Reviewers) }
    }
}

Describe 'Invoke-CIPPStandardEnableAppConsentRequests report' {
    BeforeEach {
        Mock New-GraphGetRequest {
            if ($uri -match 'adminConsentRequestPolicy') { $script:Policy }
            elseif ($uri -match "MSP%20Support") { @([PSCustomObject]@{ id = 'user-1'; displayName = 'MSP Support'; userPrincipalName = 'msp_support#EXT#@contoso.onmicrosoft.com' }) }
            else { @() }
        }
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
        Mock Set-CIPPStandardsCompareField { }
        Mock Add-CIPPBPAField { }
    }

    It 'is compliant when the configured role is present alongside extra hand-added reviewers' {
        Set-Policy @((New-RoleReviewer $script:GA), (New-RoleReviewer $script:SecAdmin), (New-UserReviewer 'someone-else'))

        Invoke-CIPPStandardEnableAppConsentRequests -Tenant $script:Tenant -Settings @{ report = $true }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            (ConvertTo-Json $CurrentValue -Compress) -eq (ConvertTo-Json $ExpectedValue -Compress)
        }
    }

    It 'names a configured role that is missing from the reviewers' {
        Set-Policy @((New-RoleReviewer $script:GA))
        $Settings = @{ report = $true; ReviewerRoles = @([PSCustomObject]@{ label = 'Security Administrator'; value = $script:SecAdmin }) }

        Invoke-CIPPStandardEnableAppConsentRequests -Tenant $script:Tenant -Settings $Settings

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($CurrentValue.MissingReviewerRoles) -join ',' -eq 'Security Administrator' -and @($ExpectedValue.MissingReviewerRoles).Count -eq 0
        }
    }

    It 'matches a configured user present by id, and grades a name with no account as missing' {
        Set-Policy @((New-RoleReviewer $script:GA), (New-UserReviewer 'user-1'))
        $Settings = @{ report = $true; ReviewerUsers = @('MSP Support', 'Nobody Here') }

        Invoke-CIPPStandardEnableAppConsentRequests -Tenant $script:Tenant -Settings $Settings

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($CurrentValue.MissingReviewerUsers) -join ',' -eq 'Nobody Here' -and @($CurrentValue.MissingReviewerRoles).Count -eq 0
        }
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like '*not added as reviewer*' }
    }
}
