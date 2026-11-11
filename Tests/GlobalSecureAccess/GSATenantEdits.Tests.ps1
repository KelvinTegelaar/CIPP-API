BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Set-CIPPGSAFilteringPolicy { param($TenantFilter, $Policy, $Current) }
    function Set-CIPPGSAProfileLinks { param($TenantFilter, $ProfileId, $ProfileName, $Links, $Current) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    foreach ($Helper in 'Get-CippErrorStatusCode', 'Get-CippBulkStatusCode', 'ConvertTo-CIPPGSAFilteringRule', 'ConvertTo-CIPPGSAProfileLink') { . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper.ps1") }
    foreach ($Name in 'Invoke-EditGSAFilteringPolicy', 'Invoke-EditGSASecurityProfile') { . (Join-Path $Folder "$Name.ps1") }

    $script:Id = '11111111-2222-3333-4444-555555555555'
    function Invoke-Edit([string]$Endpoint, [hashtable]$Body) {
        $Body.tenantFilter = 'contoso.com'
        & "Invoke-$Endpoint" -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Body = [pscustomobject]$Body })
    }
    function Get-ProfileBody { @{ ID = $script:Id; name = 'Staff'; priority = 1000; state = 'enabled'; policies = @(@{ policy = @{ label = 'Block'; value = 'pol-1' }; priority = 100 }) } }
}

Describe 'Invoke-EditGSAFilteringPolicy' {
    BeforeEach {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Id; name = 'Old'; policyRules = @() } }
        Mock Set-CIPPGSAFilteringPolicy { $script:Id }
    }

    It 'rejects a bad id, name, action or rules before calling Graph' {
        $Response = Invoke-Edit 'EditGSAFilteringPolicy' @{ ID = 'x'; name = ''; action = 'deny'; policyRules = @() }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Be "Invalid filtering policy: ID must be the id (a GUID) of the filtering policy; name is required; action must be block or allow, not 'deny'; at least one rule is required"
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'converges the tenant policy to the edited rules' {
        $Response = Invoke-Edit 'EditGSAFilteringPolicy' @{ ID = $script:Id; name = 'Block risky'; action = 'block'; policyRules = @(@{ name = 'c'; ruleType = 'webCategory'; destinations = @('Weapons', 'Gambling') }) }
        $Response.Body.Results | Should -Be "Updated filtering policy 'Block risky'"
        Should -Invoke Set-CIPPGSAFilteringPolicy -Times 1 -ParameterFilter {
            $Current.name -eq 'Old' -and $Policy.name -eq 'Block risky' -and ($Policy.policyRules[0].destinations.name -join ',') -eq 'Gambling,Weapons'
        }
    }
}

Describe 'Invoke-EditGSASecurityProfile' {
    BeforeEach {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Id; name = 'Staff'; priority = 1000; policies = @() } } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'pol-1'; name = 'Block risky' } } -ParameterFilter { $uri -like '*/filteringPolicies' }
        Mock New-GraphPOSTRequest {}
        Mock Set-CIPPGSAProfileLinks { [pscustomobject]@{ state = 'success'; resultText = "Linked 'Block risky' to security profile 'Staff'" } }
    }

    It 'patches the profile, then sets its links using the tenant policy names' {
        $Response = Invoke-Edit 'EditGSASecurityProfile' (Get-ProfileBody)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results.resultText) | Should -Be @("Updated security profile 'Staff'", "Linked 'Block risky' to security profile 'Staff'")
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $type -eq 'PATCH' -and ($body | ConvertFrom-Json).priority -eq 1000 }
        Should -Invoke Set-CIPPGSAProfileLinks -Times 1 -ParameterFilter { $Links[0].policyId -eq 'pol-1' -and $Links[0].policyName -eq 'Block risky' -and $Links[0].loggingState -eq 'enabled' }
    }

    It 'refuses a link to a policy the tenant does not have' {
        $Body = Get-ProfileBody
        $Body.policies = @(@{ policy = @{ label = 'Gone'; value = 'pol-9' }; priority = 100 })
        $Response = Invoke-Edit 'EditGSASecurityProfile' $Body
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike "*these filtering policies do not exist in the tenant: 'Gone'"
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'keeps the baseline profile at 65000 and keeps other profiles off it' {
        $Body = Get-ProfileBody
        $Body.priority = 65000
        (Invoke-Edit 'EditGSASecurityProfile' $Body).Body.Results[0].resultText | Should -BeLike '*65000 belongs to the baseline profile'
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Id; name = 'Baseline profile'; priority = 65000; policies = @() } } -ParameterFilter { $uri -like '*/filteringProfiles/*' }
        (Invoke-Edit 'EditGSASecurityProfile' (Get-ProfileBody)).Body.Results[0].resultText | Should -BeLike '*The baseline profile keeps priority 65000'
        $Body.name = 'Baseline profile'
        (Invoke-Edit 'EditGSASecurityProfile' $Body).StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
    }

    It 'reports 207 when a link write fails after the profile updated' {
        Mock Set-CIPPGSAProfileLinks { [pscustomobject]@{ state = 'error'; resultText = 'Failed to link' } }
        (Invoke-Edit 'EditGSASecurityProfile' (Get-ProfileBody)).StatusCode | Should -Be 207
    }
}
