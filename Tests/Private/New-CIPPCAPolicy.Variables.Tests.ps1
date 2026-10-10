# Pester tests for custom variables on the CA deploy path, run through the real
# Get-CIPPTextReplacement so a variable's type and value reach New-CIPPCAPolicy exactly as in production.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPNamedLocationRange.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Remove-ODataProperties.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTextReplacement.ps1')

    $script:UserId = '10000000-0000-0000-0000-000000000001'
    $script:UserId2 = '10000000-0000-0000-0000-000000000002'
    $script:GroupId = '20000000-0000-0000-0000-000000000001'
    $script:SiteAId = '30000000-0000-0000-0000-00000000000a'
    $script:SiteBId = '30000000-0000-0000-0000-00000000000b'

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'cust-1'; defaultDomainName = 'customer.example.com'; displayName = 'Customer' } }
    function Get-CIPPSchemaExtensions { }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTable { [CmdletBinding()] param($tablename) @{} }
    function Get-CIPPAzDataTableEntity {
        [CmdletBinding()] param($filter)
        if ($filter -match "PartitionKey eq 'AllTenants'") { return $script:VariableRows }
        @()
    }
    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp, $ScheduleRetry)
        $body = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $body -EscapeForJson
        $script:GraphWrites.Add(@{ Uri = $uri; Type = $type; Body = $body })
        if ($uri -match 'namedLocations$') {
            $Name = ($body | ConvertFrom-Json).displayName
            return [pscustomobject]@{ id = @{ 'Site A' = $script:SiteAId; 'Site B' = $script:SiteBId; 'Allowed Countries' = $script:SiteAId; 'Office IPs' = $script:SiteBId }[$Name]; displayName = $Name }
        }
        [pscustomobject]@{ id = 'created-policy-id' }
    }
    function New-GraphGETRequest {
        [CmdletBinding()] param($uri, $tenantid, $asApp, [switch]$ComplexFilter)
        if ($uri -match 'namedLocations\?') { $script:LocationFetches++; return $script:TenantLocations }
        if ($uri -match 'namedLocations/(?<id>[^/?]+)$') { return [pscustomobject]@{ id = $Matches.id } }
        throw "Unexpected live Graph GET in test: $uri"
    }
    function New-GraphBulkRequest {
        [CmdletBinding()] param($Requests, $tenantid, $asapp)
        $script:DirectoryFetches++
        @(
            [pscustomobject]@{ id = 'users'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:UserId; displayName = 'Break Glass' }, [pscustomobject]@{ id = $script:UserId2; displayName = 'Second Admin' }) } }
            [pscustomobject]@{ id = 'groups'; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:GroupId; displayName = 'CA Exclusions' }) } }
        )
    }
    function New-CIPPGroup { param($GroupObject, $TenantFilter, $APIName) throw 'New-CIPPGroup should not be called' }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $TenantFilter, $Headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Start-Sleep { [CmdletBinding()] param($Seconds) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPCAPolicy.ps1')

    function New-VariableRow {
        param([string]$Name, [string]$Value, [string]$VariableType)
        [pscustomobject]@{ RowKey = $Name; Value = $Value; VariableType = $VariableType }
    }

    # Builds a template whose users/locations blocks are spliced in verbatim, so a test can place a
    # token in an array element ("[\"%x%\"]") or as the whole value ("\"%x%\"").
    function New-Template {
        param([string]$Users = '"includeUsers": ["All"]', [string]$Locations, [string]$LocationInfo)
        $Conditions = @(
            "`"users`": { $Users }"
            '"applications": { "includeApplications": ["All"] }'
            '"clientAppTypes": ["all"]'
            if ($Locations) { "`"locations`": { $Locations }" }
        ) -join ', '
        $Extra = if ($LocationInfo) { ", `"LocationInfo`": $LocationInfo" } else { '' }
        "{ `"displayName`": `"Variable test policy`", `"state`": `"disabled`", `"conditions`": { $Conditions }, `"grantControls`": { `"operator`": `"OR`", `"builtInControls`": [`"mfa`"] }$Extra }"
    }

    function Invoke-Deploy {
        param([string]$Template, [string]$ReplacePattern = 'none')
        $script:GraphWrites = [System.Collections.Generic.List[object]]::new()
        $script:LocationFetches = 0
        $script:DirectoryFetches = 0
        $null = New-CIPPCAPolicy -RawJSON $Template -TenantFilter 'customer.example.com' -State 'disabled' -Overwrite $true `
            -ReplacePattern $ReplacePattern -PreloadedCAPolicies @([pscustomobject]@{ id = 'other-id'; displayName = 'Unrelated policy' })
        $PolicyWrite = $script:GraphWrites | Where-Object { $_.Uri -match '/policies$' } | Select-Object -Last 1
        $PolicyWrite.Body | ConvertFrom-Json
    }
}

Describe 'New-CIPPCAPolicy custom variables' {
    BeforeEach {
        $script:TenantLocations = @(
            [pscustomobject]@{ id = $script:SiteAId; displayName = 'Site A' }
            [pscustomobject]@{ id = $script:SiteBId; displayName = 'Site B' }
        )
        $script:VariableRows = @(
            New-VariableRow -Name 'breakglass' -Value 'Break Glass'
            New-VariableRow -Name 'exclgroup' -Value 'CA Exclusions'
            New-VariableRow -Name 'nobody' -Value 'Nobody Here'
            New-VariableRow -Name 'sitea' -Value 'Site A'
            New-VariableRow -Name 'sites' -Value '["Site A","Site B"]' -VariableType 'json'
            New-VariableRow -Name 'sitelist' -Value '["Site A","Site B"]' -VariableType 'list'
            New-VariableRow -Name 'emptylist' -Value '[]' -VariableType 'list'
            New-VariableRow -Name 'userlist' -Value '["Break Glass","Second Admin"]' -VariableType 'list'
            New-VariableRow -Name 'grouplist' -Value '["CA Exclusions"]' -VariableType 'list'
            New-VariableRow -Name 'countries' -Value '["NL","BE"]' -VariableType 'list'
            New-VariableRow -Name 'officeips' -Value '["203.0.113.0/24","2001:db8::/48"]' -VariableType 'list'
            New-VariableRow -Name 'sitedefs' -Value '[{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Site A","isTrusted":true,"ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"192.0.2.0/24"}]},{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Site B","isTrusted":true,"ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"198.51.100.0/24"}]}]' -VariableType 'json'
        )
    }

    Context 'user and group lists with displayName replacement' {
        It 'resolves a user name from a variable to its id' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeUsers": ["%breakglass%"]') -ReplacePattern 'displayName'
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
        }

        It 'drops a user name that matches nobody' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeUsers": ["%breakglass%", "%nobody%"]') -ReplacePattern 'displayName'
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
        }

        It 'resolves a group name from a variable to its id' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeGroups": ["%exclgroup%"]') -ReplacePattern 'displayName'
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
        }

        It 'throws for a group name that matches nothing when groups are not created' {
            { Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeGroups": ["%nobody%"]') -ReplacePattern 'displayName' } |
                Should -Throw "*Group 'Nobody Here' not found*"
        }
    }

    Context 'user and group lists without replacement' {
        It 'sends ids unchanged without reading the directory' {
            $Policy = Invoke-Deploy (New-Template -Users ('"includeUsers": ["All"], "excludeUsers": ["{0}"], "excludeGroups": ["{1}"]' -f $script:UserId, $script:GroupId))
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
            $script:DirectoryFetches | Should -Be 0
        }

        It 'resolves a group name without creating groups' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeGroups": ["%exclgroup%"]')
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
        }

        It 'throws for a group name that matches nothing' {
            { Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeGroups": ["%nobody%"]') } |
                Should -Throw "*Group 'Nobody Here' not found*"
        }

        It 'resolves a user name' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeUsers": ["%breakglass%"]')
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
        }

        It 'throws for a user name that matches nobody instead of dropping it' {
            { Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeUsers": ["%breakglass%", "%nobody%"]') } |
                Should -Throw "*User 'Nobody Here' not found*"
        }

        It 'resolves every name in a list variable' {
            $Policy = Invoke-Deploy (New-Template -Users '"includeUsers": ["All"], "excludeUsers": ["%userlist%"], "excludeGroups": ["%grouplist%"]')
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId, $script:UserId2)
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
        }
    }

    Context 'location lists' {
        It 'passes All, AllTrusted and ids through without reading named locations' {
            $Policy = Invoke-Deploy (New-Template -Locations ('"includeLocations": ["All"], "excludeLocations": ["AllTrusted", "{0}"]' -f $script:SiteAId))
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('AllTrusted', $script:SiteAId)
            $script:LocationFetches | Should -Be 0
        }

        It 'resolves a location name that is not in LocationInfo against the tenant' {
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["%sitea%"]')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:SiteAId)
        }

        It 'resolves every location in a list variable alongside other entries' {
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["AllTrusted", "%sitelist%"]')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('AllTrusted', $script:SiteAId, $script:SiteBId)
        }

        It 'drops an empty list variable from the list' {
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["AllTrusted", "%emptylist%"]')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('AllTrusted')
        }

        It 'throws for a location name the tenant does not have' {
            { Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["%nobody%"]') } |
                Should -Throw "*Named location 'Nobody Here'*was not found*"
        }

        It 'resolves a json variable that fills the whole list against LocationInfo' {
            $Info = '[{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Site A","ipRanges":[]},{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Site B","ipRanges":[]}]'
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": "%sites%"' -LocationInfo $Info)
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:SiteAId, $script:SiteBId)
        }

        It 'creates every location from a json variable used as a LocationInfo element' {
            $script:TenantLocations = @()
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": "%sites%"' -LocationInfo '["%sitedefs%"]')
            $Creates = @($script:GraphWrites | Where-Object { $_.Uri -match 'namedLocations$' -and $_.Type -eq 'POST' })
            @($Creates | ForEach-Object { ($_.Body | ConvertFrom-Json).displayName }) | Should -Be @('Site A', 'Site B')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:SiteAId, $script:SiteBId)
        }

        It 'fills a template location''s countries and IP ranges from list variables' {
            $script:TenantLocations = @()
            # The IP range is the shape the policy builder saves for a line holding a variable.
            $Info = '[{"@odata.type":"#microsoft.graph.countryNamedLocation","displayName":"Allowed Countries","countriesAndRegions":["%countries%"],"includeUnknownCountriesAndRegions":false,"countryLookupMethod":"clientIpAddress"},{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Office IPs","isTrusted":true,"ipRanges":[{"@odata.type":"#microsoft.graph.iPv4CidrRange","cidrAddress":"%officeips%"}]}]'
            $Policy = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["Allowed Countries", "Office IPs"]' -LocationInfo $Info)
            $Created = @($script:GraphWrites | Where-Object { $_.Uri -match 'namedLocations$' -and $_.Type -eq 'POST' } | ForEach-Object { $_.Body | ConvertFrom-Json })

            @(($Created | Where-Object displayName -EQ 'Allowed Countries').countriesAndRegions) | Should -Be @('NL', 'BE')
            $Ranges = @(($Created | Where-Object displayName -EQ 'Office IPs').ipRanges)
            @($Ranges.cidrAddress) | Should -Be @('203.0.113.0/24', '2001:db8::/48')
            @($Ranges.'@odata.type') | Should -Be @('#microsoft.graph.iPv4CidrRange', '#microsoft.graph.iPv6CidrRange')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:SiteAId, $script:SiteBId)
        }

        It 'turns plain CIDR strings from a list variable into range objects' {
            $script:TenantLocations = @()
            $Info = '[{"@odata.type":"#microsoft.graph.ipNamedLocation","displayName":"Office IPs","isTrusted":true,"ipRanges":["%officeips%"]}]'
            $null = Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["Office IPs"]' -LocationInfo $Info)
            $Created = $script:GraphWrites | Where-Object { $_.Uri -match 'namedLocations$' -and $_.Type -eq 'POST' } | Select-Object -First 1
            $Ranges = @(($Created.Body | ConvertFrom-Json).ipRanges)
            @($Ranges.cidrAddress) | Should -Be @('203.0.113.0/24', '2001:db8::/48')
            @($Ranges.'@odata.type') | Should -Be @('#microsoft.graph.iPv4CidrRange', '#microsoft.graph.iPv6CidrRange')
        }

        It 'throws for an undefined variable, naming it' {
            { Invoke-Deploy (New-Template -Locations '"includeLocations": ["All"], "excludeLocations": ["%notdefined%"]') } |
                Should -Throw '*uses %notdefined%, which is not defined for customer.example.com*'
            $script:GraphWrites.Count | Should -Be 0
        }
    }
}
