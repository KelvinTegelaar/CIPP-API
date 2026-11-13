BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    foreach ($Name in 'Invoke-ListGSAFilteringPolicies', 'Invoke-ListGSASecurityProfiles', 'Invoke-RemoveGSAFilteringPolicy', 'Invoke-RemoveGSASecurityProfile') { . (Join-Path $Folder "$Name.ps1") }

    $script:Guid = '11111111-2222-3333-4444-555555555555'
    function Get-Profiles {
        [pscustomobject]@{ id = 'base'; name = 'Baseline profile'; priority = 65000; policies = @([pscustomobject]@{ priority = 65000; policy = [pscustomobject]@{ id = 'all'; name = 'All websites' } }); conditionalAccessPolicies = @() }
        [pscustomobject]@{ id = 'staff'; name = 'Staff'; priority = 1000; policies = @(
                [pscustomobject]@{ priority = 200; policy = [pscustomobject]@{ id = $script:Guid; name = 'Block risky' } }
                [pscustomobject]@{ priority = 100; policy = [pscustomobject]@{ id = 'p2'; name = 'Allow partners' } }
            ); conditionalAccessPolicies = @([pscustomobject]@{ id = 'ca1'; displayName = 'Staff web filtering' })
        }
    }
    function Invoke-Remove([string]$Endpoint, $ID) { & "Invoke-$Endpoint" -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; ID = $ID } }) }
}

Describe 'GSA tenant lists' {
    BeforeEach {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { Get-Profiles } -ParameterFilter { $uri -like '*/filteringProfiles?*' }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = $script:Guid; name = 'Block risky'; action = 'block'; policyRules = @() }
            [pscustomobject]@{ id = 'orphan'; name = 'Unused'; action = 'block'; policyRules = @() }
        } -ParameterFilter { $uri -like '*/filteringPolicies?*' }
    }

    It 'adds the linking security profiles to each policy, empty when none link it' {
        $Response = Invoke-ListGSAFilteringPolicies -Request ([pscustomobject]@{ Query = @{ tenantFilter = 'contoso.com' } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        ($Response.Body | Where-Object id -EQ $script:Guid).securityProfiles | Should -Be @('Staff')
        $Orphan = $Response.Body | Where-Object id -EQ 'orphan'
        $Orphan.securityProfiles.Count | Should -Be 0
        ($Orphan | ConvertTo-Json -Compress) | Should -BeLike '*"securityProfiles":`[`]*'
        Should -Invoke New-GraphGetRequest -ParameterFilter { $AsApp -eq $true } -Times 3 -Exactly
    }

    It 'adds ordered policy links and the CA policies applying each profile' {
        $Staff = (Invoke-ListGSASecurityProfiles -Request ([pscustomobject]@{ Query = @{ tenantFilter = 'contoso.com' } })).Body | Where-Object id -EQ 'staff'
        $Staff.filteringPolicies | Should -Be @('100: Allow partners', '200: Block risky')
        $Staff.conditionalAccessPolicyNames | Should -Be @('Staff web filtering')
    }

    It 'explains a tenant that is not onboarded with a 400' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'offboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        $Response = Invoke-ListGSASecurityProfiles -Request ([pscustomobject]@{ Query = @{ tenantFilter = 'contoso.com' } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*not onboarded to Global Secure Access'
    }
}

Describe 'GSA tenant deletes' {
    BeforeEach {
        Mock New-GraphGetRequest { Get-Profiles } -ParameterFilter { $uri -like '*/filteringProfiles?*' }
        Mock New-GraphPOSTRequest {}
    }

    It 'rejects an id that is not a GUID before calling Graph' {
        foreach ($Endpoint in 'RemoveGSAFilteringPolicy', 'RemoveGSASecurityProfile') {
            (Invoke-Remove $Endpoint '../filteringPolicies').StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'refuses to delete a policy a profile links, naming the profile' {
        $Response = Invoke-Remove 'RemoveGSAFilteringPolicy' $script:Guid
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*linked by security profiles: Staff. Unlink it from them first.'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'deletes an unlinked policy' {
        $Other = '99999999-2222-3333-4444-555555555555'
        (Invoke-Remove 'RemoveGSAFilteringPolicy' $Other).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $type -eq 'DELETE' -and $uri -like "*/filteringPolicies/$Other" -and $AsApp -eq $true }
    }

    It 'refuses the baseline profile and a profile a CA policy applies' {
        Mock New-GraphGetRequest { (Get-Profiles)[0] } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        (Invoke-Remove 'RemoveGSASecurityProfile' $script:Guid).Body.Results | Should -BeLike "*'Baseline profile' is the tenant's built-in baseline profile*"
        Mock New-GraphGetRequest { (Get-Profiles)[1] } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        $Response = Invoke-Remove 'RemoveGSASecurityProfile' $script:Guid
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike "*'Staff' is applied by Conditional Access policies: Staff web filtering*"
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'deletes a profile no CA policy applies' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Guid; name = 'Old'; priority = 1200; conditionalAccessPolicies = @() } } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        (Invoke-Remove 'RemoveGSASecurityProfile' $script:Guid).Body.Results | Should -Be "Deleted security profile 'Old'"
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $type -eq 'DELETE' }
    }
}
