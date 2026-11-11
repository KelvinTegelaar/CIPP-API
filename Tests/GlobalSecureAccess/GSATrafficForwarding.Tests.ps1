BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-NormalizedError { param($Message) $Message }
    foreach ($Helper in 'Get-CippErrorStatusCode', 'Get-CippBulkStatusCode', 'ConvertTo-CIPPGSAForwardingRule', 'ConvertFrom-CIPPGSAForwardingRule') { . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper.ps1") }
    foreach ($Name in 'Invoke-ListGSATrafficForwarding', 'Invoke-ListGSARemoteNetworks', 'Invoke-EditGSATrafficForwardingProfile') { . (Join-Path $Folder "$Name.ps1") }

    $script:Internet = '11111111-1111-1111-1111-111111111111'
    $script:M365 = '22222222-2222-2222-2222-222222222222'
    $script:Private = '33333333-3333-3333-3333-333333333333'
    $script:Group = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:User = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:Graph = 'https://graph.microsoft.com/beta'

    function Get-TrafficProfiles {
        [pscustomobject]@{ id = $script:M365; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false; servicePrincipal = @{ id = 'sp-m365'; appId = 'app-m365' }; policies = @([pscustomobject]@{ id = 'l1'; state = 'enabled'; policy = [pscustomobject]@{ id = 'p1'; name = 'Exchange Online' } }) }
        [pscustomobject]@{ id = $script:Internet; name = 'Internet'; state = 'disabled'; trafficForwardingType = 'internet'; isCustomProfile = $false; servicePrincipal = @{ id = 'sp-inet'; appId = 'app-inet' }; policies = @(
                [pscustomobject]@{ id = 'l2'; state = 'enabled'; policy = [pscustomobject]@{ id = 'bypass-pol'; name = 'Custom bypass' } }
                [pscustomobject]@{ id = 'l3'; state = 'enabled'; policy = [pscustomobject]@{ id = 'acquire-pol'; name = 'Custom Acquire' } }
            )
        }
        [pscustomobject]@{ id = $script:Private; name = 'Private'; state = 'enabled'; trafficForwardingType = 'private'; isCustomProfile = $false; servicePrincipal = @{ id = 'sp-priv'; appId = 'app-priv' }; policies = @() }
        [pscustomobject]@{ id = 'custom'; name = 'My app'; state = 'enabled'; trafficForwardingType = 'private'; isCustomProfile = $true; servicePrincipal = @{ id = 'sp-x' }; policies = @() }
    }
    function Get-BypassRules {
        [pscustomobject]@{ id = 'r1'; protocol = 'tcp'; ports = @('0-65535'); destinations = @([pscustomobject]@{ value = 'contoso.com' }) }
        [pscustomobject]@{ id = 'r2'; protocol = 'udp'; ports = @('0-65535'); destinations = @([pscustomobject]@{ value = 'contoso.com' }) }
    }
    function Get-Networks {
        [pscustomobject]@{ id = 'net-a'; name = 'Sydney'; region = 'australiaEast'; forwardingProfiles = @([pscustomobject]@{ id = $script:M365; name = 'Microsoft 365'; trafficForwardingType = 'm365' }) }
        [pscustomobject]@{ id = 'net-b'; name = 'Perth'; region = 'australiaEast'; forwardingProfiles = @([pscustomobject]@{ id = $script:M365 }, [pscustomobject]@{ id = $script:Internet }) }
    }
    function Invoke-Edit([hashtable]$Body) {
        $Body.tenantFilter = 'contoso.com'
        Invoke-EditGSATrafficForwardingProfile -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'EditGSATrafficForwardingProfile' }; Body = [pscustomobject]$Body })
    }
    $script:Query = [pscustomobject]@{ Query = @{ tenantFilter = 'contoso.com' } }
}

Describe 'Invoke-ListGSATrafficForwarding' {
    BeforeEach {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { Get-TrafficProfiles } -ParameterFilter { $uri -eq "$script:Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" }
        Mock New-GraphGetRequest { Get-Networks } -ParameterFilter { $uri -like '*/remoteNetworks?*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ appRoleAssignmentRequired = $false } } -ParameterFilter { $uri -like '*/servicePrincipals/sp-*?$select=appRoleAssignmentRequired' }
        Mock New-GraphGetRequest { [pscustomobject]@{ appRoleAssignmentRequired = $true } } -ParameterFilter { $uri -like '*/servicePrincipals/sp-inet?$select=appRoleAssignmentRequired' }
        Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*/appRoleAssignedTo?*' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'as1'; principalId = $script:Group; principalType = 'Group'; principalDisplayName = 'Staff'; appRoleId = 'x' } } -ParameterFilter { $uri -like '*/sp-inet/appRoleAssignedTo?*' }
        Mock New-GraphGetRequest { Get-BypassRules } -ParameterFilter { $uri -like '*/forwardingPolicies/bypass-pol/policyRules' }
        Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*/forwardingPolicies/acquire-pol/policyRules' }
    }

    It 'returns one row per built-in profile with assignment, policies, remote networks and custom rules' {
        $Response = Invoke-ListGSATrafficForwarding -Request $script:Query
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.name) | Should -Be @('Microsoft 365', 'Internet', 'Private')
        $M365, $Internet, $Private = $Response.Body
        $M365.assignedToAllUsers | Should -BeTrue
        $M365.assignment | Should -Be 'All users'
        @($M365.remoteNetworks.name) | Should -Be @('Sydney', 'Perth')
        $M365.policies[0].policyName | Should -Be 'Exchange Online'
        $M365.policies[0].policyId | Should -Be 'p1'
        $Internet.assignedToAllUsers | Should -BeFalse
        $Internet.assignment | Should -Be '1 users and groups'
        $Internet.assignees[0].id | Should -Be 'as1'
        $Internet.assignees[0].principalType | Should -Be 'Group'
        @($Internet.remoteNetworks.name) | Should -Be @('Perth')
        # a single site or an empty list must stay a JSON array for the edit page
        (ConvertTo-Json -Compress -Depth 5 -InputObject $Internet.remoteNetworks) | Should -BeLike '[[]*'
        (ConvertTo-Json -Compress -Depth 5 -InputObject $Private.remoteNetworks) | Should -Be '[]'
        $Internet.customBypass.destination | Should -Be 'contoso.com'
        $Internet.customBypass.protocols | Should -Be 'tcp,udp'
        $Internet.customAcquire.Count | Should -Be 0
        $Private.PSObject.Properties.Name | Should -Not -Contain 'customBypass'
        $Private.remoteNetworks.Count | Should -Be 0
        Should -Invoke New-GraphGetRequest -ParameterFilter { $AsApp -ne $true } -Times 0 -Exactly
    }

    It 'links Conditional Access policies the way the portal does, and warns about a missing license' {
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'ca-all'; displayName = 'All apps MFA'; state = 'enabled'; conditions = @{ applications = @{ includeApplications = @('All'); excludeApplications = @('app-inet') } } }
            [pscustomobject]@{ id = 'ca-priv'; displayName = 'Private only'; state = 'enabledForReportingButNotEnforced'; conditions = @{ applications = @{ includeApplications = @('app-priv') } } }
            [pscustomobject]@{ id = 'ca-o365'; displayName = 'Office'; state = 'enabled'; conditions = @{ applications = @{ includeApplications = @('Office365') } } }
        } -ParameterFilter { $uri -like '*/identity/conditionalAccess/policies*' }
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; Entra_Premium_Internet_Access = $true } }
        $M365, $Internet, $Private = (Invoke-ListGSATrafficForwarding -Request $script:Query).Body
        @($M365.linkedConditionalAccessPolicies.displayName) | Should -Be @('All apps MFA')
        @($Internet.linkedConditionalAccessPolicies).Count | Should -Be 0
        (ConvertTo-Json -Compress -InputObject $Internet.linkedConditionalAccessPolicies) | Should -Be '[]'
        (ConvertTo-Json -Compress -Depth 5 -InputObject $Private.linkedConditionalAccessPolicies) | Should -BeLike '[[]*'
        @($Private.linkedConditionalAccessPolicies.id) | Should -Be @('ca-priv')
        $M365.licenseWarning | Should -BeNullOrEmpty
        $Internet.licenseWarning | Should -BeNullOrEmpty
        $Private.licenseWarning | Should -Be 'The tenant is missing the license needed to use this profile (Microsoft Entra Private Access).'
    }

    It 'gives no license warning when the license cannot be read, and names unread Conditional Access in readErrors' {
        Mock Get-CIPPTenantCapabilities { throw 'down' }
        Mock New-GraphGetRequest { throw 'Forbidden' } -ParameterFilter { $uri -like '*/identity/conditionalAccess/policies*' }
        $Rows = (Invoke-ListGSATrafficForwarding -Request $script:Query).Body
        @($Rows.Where({ $_.licenseWarning })).Count | Should -Be 0
        $Rows[0].linkedConditionalAccessPolicies | Should -BeNullOrEmpty
        $Rows[0].readErrors | Should -Contain 'Conditional Access policies: Forbidden'
    }

    It 'keeps the page when one profile part fails, nulling it and naming it in readErrors' {
        Mock New-GraphGetRequest { throw 'Forbidden' } -ParameterFilter { $uri -like '*/sp-inet/appRoleAssignedTo?*' }
        Mock New-GraphGetRequest { throw 'Boom' } -ParameterFilter { $uri -like '*/forwardingPolicies/acquire-pol/policyRules' }
        $Response = Invoke-ListGSATrafficForwarding -Request $script:Query
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Internet = $Response.Body[1]
        $Internet.assignedToAllUsers | Should -BeNullOrEmpty
        $Internet.assignees | Should -BeNullOrEmpty
        $Internet.assignment | Should -Be 'Unknown'
        $Internet.customAcquire | Should -BeNullOrEmpty
        $Internet.customBypass.destination | Should -Be 'contoso.com'
        $Internet.readErrors | Should -Be @('assignment: Forbidden', 'Custom Acquire rules: Boom')
        $Response.Body[0].readErrors.Count | Should -Be 0
    }

    It 'explains a tenant that is not onboarded with a 400' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'offboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        $Response = Invoke-ListGSATrafficForwarding -Request $script:Query
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*not onboarded to Global Secure Access'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }
}

Describe 'Invoke-ListGSARemoteNetworks' {
    BeforeEach {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'onboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        Mock New-GraphGetRequest { Get-Networks } -ParameterFilter { $uri -eq "$script:Graph/networkAccess/connectivity/remoteNetworks?`$expand=forwardingProfiles(`$select=id,name,trafficForwardingType)" }
        Mock New-GraphGetRequest {
            [pscustomobject]@{
                id = 'dl1'; name = 'Edge 1'; ipAddress = '203.0.113.10'; deviceVendor = 'other'; bandwidthCapacityInMbps = 'mbps250'
                bgpConfiguration = [pscustomobject]@{ asn = 65001; localIpAddress = '10.0.0.1' }
                tunnelConfiguration = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.tunnelConfigurationIKEv2Default'; preSharedKey = 'SuperSecretPsk123' }
            }
        } -ParameterFilter { $uri -like '*/remoteNetworks/net-a/deviceLinks' }
        Mock New-GraphGetRequest { throw 'Boom' } -ParameterFilter { $uri -like '*/remoteNetworks/net-b/deviceLinks' }
    }

    It 'projects device links without their tunnel configuration' {
        $Response = Invoke-ListGSARemoteNetworks -Request $script:Query
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Sydney = $Response.Body[0]
        $Sydney.profiles[0].trafficForwardingType | Should -Be 'm365'
        $Sydney.deviceLinks[0].asn | Should -Be 65001
        @($Sydney.deviceLinks[0].PSObject.Properties.Name) | Should -Be @('name', 'ipAddress', 'deviceVendor', 'bandwidthCapacityInMbps', 'asn')
        $Json = ConvertTo-Json -Depth 20 -InputObject $Response.Body
        $Json | Should -Not -BeLike '*SuperSecretPsk123*'
        $Json | Should -Not -BeLike '*preSharedKey*'
        $Json | Should -Not -BeLike '*tunnelConfiguration*'
        Should -Invoke New-GraphGetRequest -ParameterFilter { $AsApp -ne $true } -Times 0 -Exactly
    }

    It 'nulls the device links of a site whose links cannot be read and keeps the rest' {
        $Response = Invoke-ListGSARemoteNetworks -Request $script:Query
        $Response.Body[1].name | Should -Be 'Perth'
        $Response.Body[1].deviceLinks | Should -BeNullOrEmpty
        $Response.Body[1].profiles.Count | Should -Be 2
    }

    It 'explains a tenant that is not onboarded with a 400' {
        Mock New-GraphGetRequest { [pscustomobject]@{ onboardingStatus = 'offboarded' } } -ParameterFilter { $uri -like '*/tenantStatus' }
        (Invoke-ListGSARemoteNetworks -Request $script:Query).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}

Describe 'Invoke-EditGSATrafficForwardingProfile' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphGetRequest { @(Get-TrafficProfiles).Where({ $_.id -eq $script:Internet })[0] } -ParameterFilter { $uri -eq "$script:Graph/networkAccess/forwardingProfiles/$($script:Internet)?`$expand=policies(`$expand=policy)" }
        Mock New-GraphGetRequest { @(Get-TrafficProfiles).Where({ $_.id -eq $script:M365 })[0] } -ParameterFilter { $uri -like "*/forwardingProfiles/$($script:M365)?*" }
        Mock New-GraphGetRequest { @(Get-TrafficProfiles).Where({ $_.id -eq $script:Private })[0] } -ParameterFilter { $uri -like "*/forwardingProfiles/$($script:Private)?*" }
        Mock New-GraphGetRequest { [pscustomobject]@{ appRoleAssignmentRequired = $true } } -ParameterFilter { $uri -like '*/servicePrincipals/sp-*?$select=appRoleAssignmentRequired' }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'as1'; principalId = $script:Group; principalType = 'Group'; principalDisplayName = 'Staff' } } -ParameterFilter { $uri -like '*/appRoleAssignedTo?*' }
        Mock New-GraphGetRequest { Get-Networks } -ParameterFilter { $uri -eq "$script:Graph/networkAccess/connectivity/remoteNetworks?`$expand=forwardingProfiles(`$select=id)" }
        Mock New-GraphGetRequest { Get-BypassRules } -ParameterFilter { $uri -like '*/forwardingPolicies/bypass-pol/policyRules' }
        Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*/forwardingPolicies/acquire-pol/policyRules' }
        Mock New-GraphPOSTRequest { $script:Calls.Add([pscustomobject]@{ type = $type; uri = $uri; body = $body; AsApp = $AsApp }) }
        Mock New-GraphBulkRequest {}
        Mock Write-LogMessage {}
    }

    It 'rejects a bad id, state, all-users flag, assignee or destination before calling Graph' {
        $Response = Invoke-Edit @{ id = '../x'; state = 'on'; assignedToAllUsers = 'yes'; assignees = @(@{ value = 'nope'; label = 'Bob' }); customBypass = @('not a host!'); customAcquirePorts = '99999999'; customAcquire = @('contoso.com') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Be "Invalid traffic forwarding profile edit: id must be the id (a GUID) of the traffic forwarding profile; state must be enabled or disabled, not 'on'; assignedToAllUsers must be true or false; assignee 'Bob' needs a value that is a user or group id; customBypass: 'not a host!' is not an FQDN, IPv4 address, subnet or range; customAcquire: '99999999' is not a port or port range"
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'writes only what was sent and differs, then reports nothing changed when all matches' {
        $Response = Invoke-Edit @{ id = $script:Internet; state = 'disabled'; assignedToAllUsers = $false; assignees = @(@{ value = $script:Group; type = 'Group' }); customBypass = @('contoso.com') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results[0].resultText | Should -Be "Traffic profile 'Internet' already matches; nothing changed"
        $script:Calls.Count | Should -Be 0
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/remoteNetworks*' } -Times 0
    }

    It 'patches the state, the all-users flag and the assignment set' {
        $Response = Invoke-Edit @{ id = $script:Internet; state = 'enabled'; assignedToAllUsers = $true; assignees = @(@{ value = $script:User; label = 'Ann'; type = 'User' }) }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @(@($script:Calls).ForEach({ "$($_.type) $($_.uri)" })) | Should -Be @(
            "PATCH $script:Graph/networkAccess/forwardingProfiles/$script:Internet"
            "PATCH $script:Graph/servicePrincipals/sp-inet"
            "POST $script:Graph/servicePrincipals/sp-inet/appRoleAssignedTo"
            "DELETE $script:Graph/servicePrincipals/sp-inet/appRoleAssignedTo/as1"
        )
        $script:Calls[0].body | Should -Be '{"state":"enabled"}'
        $script:Calls[1].body | Should -Be '{"appRoleAssignmentRequired":false}'
        $script:Calls[2].body | Should -Be "{`"principalId`":`"$script:User`",`"resourceId`":`"sp-inet`",`"appRoleId`":`"00000000-0000-0000-0000-000000000000`"}"
        @($script:Calls.Where({ $_.AsApp -ne $true })).Count | Should -Be 0
        @($Response.Body.Results.resultText) | Should -Be @(
            "Set traffic profile 'Internet' to enabled"
            "Applied traffic profile 'Internet' to all users"
            "Assigned traffic profile 'Internet' to User 'Ann'"
            "Removed Group 'Staff' from traffic profile 'Internet'"
        )
        Should -Invoke Write-LogMessage -Times 4 -Exactly
    }

    It 'removes this profile from a site by sending the site''s remaining profiles as a delta body' {
        $Response = Invoke-Edit @{ id = $script:Internet; remoteNetworks = @() }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results[0].resultText | Should -Be "Removed remote network 'Perth' from traffic profile 'Internet'"
        $script:Calls.Count | Should -Be 1
        $script:Calls[0].type | Should -Be 'PATCH'
        $script:Calls[0].uri | Should -Be "$script:Graph/networkAccess/connectivity/remoteNetworks/net-b/forwardingProfiles"
        $script:Calls[0].body | Should -Be ('{"@context":"#$delta","value":[{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfile","id":"' + $script:M365 + '"}]}')
    }

    It 'adds this profile to a site, keeping the site''s other profiles' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:Internet; name = 'Internet'; state = 'enabled'; trafficForwardingType = 'internet'; servicePrincipal = @{ id = 'sp-inet' }; policies = @() } } -ParameterFilter { $uri -like "*/forwardingProfiles/$($script:Internet)?*" }
        $Response = Invoke-Edit @{ id = $script:Internet; remoteNetworks = @(@{ value = 'net-a' }, @{ value = 'net-b' }) }
        $Response.Body.Results[0].resultText | Should -Be "Added remote network 'Sydney' to traffic profile 'Internet'"
        $script:Calls.Count | Should -Be 1
        $script:Calls[0].uri | Should -BeLike '*/remoteNetworks/net-a/forwardingProfiles'
        $script:Calls[0].body | Should -Be ('{"@context":"#$delta","value":[{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfile","id":"' + $script:M365 + '"},{"@odata.type":"#microsoft.graph.networkaccess.forwardingProfile","id":"' + $script:Internet + '"}]}')
    }

    It 'refuses to leave a site with no profile, to add a disabled profile, or to use an unknown site' {
        $Response = Invoke-Edit @{ id = $script:M365; remoteNetworks = @() }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike "*Remote network 'Sydney' must keep at least one traffic profile"

        $Response = Invoke-Edit @{ id = $script:Internet; remoteNetworks = @('net-a', 'net-b') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike "*Remote network 'Sydney' can only use an enabled profile*"

        $Response = Invoke-Edit @{ id = $script:M365; remoteNetworks = @('net-a', 'net-b', 'net-z') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)

        $Response = Invoke-Edit @{ id = $script:Private; remoteNetworks = @('net-a') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $script:Calls.Count | Should -Be 0
    }

    It 'adds a disabled profile to a site when the same edit enables it, enabling first' {
        $Response = Invoke-Edit @{ id = $script:Internet; state = 'enabled'; remoteNetworks = @('net-a', 'net-b') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($script:Calls.type) | Should -Be @('PATCH', 'PATCH')
        $script:Calls[0].uri | Should -BeLike "*/forwardingProfiles/$script:Internet"
        $script:Calls[1].uri | Should -BeLike '*/remoteNetworks/net-a/forwardingProfiles'
    }

    It 'replaces custom rules one call at a time: every delete, then every create' {
        $Response = Invoke-Edit @{ id = $script:Internet; customBypass = @('fabrikam.com', '10.0.0.0/8'); customBypassPorts = '443'; customAcquire = @() }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @(@($script:Calls).ForEach({ "$($_.type) $($_.uri)" })) | Should -Be @(
            "DELETE $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules/r1"
            "DELETE $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules/r2"
            "POST $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules"
            "POST $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules"
            "POST $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules"
            "POST $script:Graph/networkAccess/forwardingPolicies/bypass-pol/policyRules"
        )
        $Created = @($script:Calls.Where({ $_.type -eq 'POST' }).ForEach({ $_.body | ConvertFrom-Json }))
        @($Created.ForEach({ "$($_.ruleType) $($_.protocol) $($_.action) $($_.ports -join ',') $($_.destinations.value -join ',')" })) | Should -Be @(
            'fqdn tcp bypass 443 fabrikam.com'
            'fqdn udp bypass 443 fabrikam.com'
            'ipSubnet tcp bypass 443 10.0.0.0/8'
            'ipSubnet udp bypass 443 10.0.0.0/8'
        )
        Should -Invoke New-GraphBulkRequest -Times 0
        @($Response.Body.Results.resultText) | Should -Be @("Updated the Custom bypass destinations of traffic profile 'Internet'")
    }

    It 'only creates rules in an empty policy, with no delete for a missing rule id' {
        $Response = Invoke-Edit @{ id = $script:Internet; customAcquire = @('contoso.com') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @(@($script:Calls).ForEach({ "$($_.type) $($_.uri)" })) | Should -Be @(
            "POST $script:Graph/networkAccess/forwardingPolicies/acquire-pol/policyRules"
            "POST $script:Graph/networkAccess/forwardingPolicies/acquire-pol/policyRules"
        )
    }

    It 'stops a policy''s replace at the first failed write and reports 207 when another change worked' {
        Mock New-GraphPOSTRequest { $script:Calls.Add([pscustomobject]@{ type = $type; uri = $uri }); if ($type -eq 'DELETE') { throw 'Conflict' } }
        $Response = Invoke-Edit @{ id = $script:Internet; state = 'enabled'; customBypass = @() }
        $Response.StatusCode | Should -Be 207
        @($script:Calls.type) | Should -Be @('PATCH', 'DELETE')
        $Response.Body.Results[1].resultText | Should -Be 'Failed to replace the Custom bypass rules: Conflict'
    }

    It 'refuses custom rules on a profile that is not the Internet profile' {
        $Response = Invoke-Edit @{ id = $script:M365; customBypass = @('contoso.com') }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results[0].resultText | Should -BeLike '*belong to the Internet profile only'
    }
}
