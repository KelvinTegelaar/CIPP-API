# Pester tests for New-CIPPCAPolicy custom-variable resolution on the named-location path.
# A template may carry %tokens% in LocationInfo and conditions.locations (per-tenant custom
# variables). These pin that tokens are resolved BEFORE the named-location existence check and
# the displayName->id mapping: an existing location must be matched (not duplicated on every
# deploy), and the policy body must reference the location's GUID, never the raw token or the
# resolved display name (Graph rejects a display name where it expects an id with error 1040).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Real dependencies - their behaviour is part of the path under test.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Remove-ODataProperties.ps1')

    # Variable substitution stub: the tenant's custom-variable map, applied the way the real
    # Get-CIPPTextReplacement does (token -> literal value), minus the Azure Table lookups.
    function Get-CIPPTextReplacement {
        [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson)
        if ($Text -isnot [string]) { return , $Text }
        $Map = @{
            'CA000_Location_Exclusion_DisplayName' = 'SLY_Lupfig-03'
            'CA000_Location_Exclusion_IP'          = '203.0.113.0/24'
        }
        foreach ($Key in $Map.Keys) {
            $Text = $Text -replace [regex]::Escape("%$Key%"), $Map[$Key]
        }
        return $Text
    }

    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp, $ScheduleRetry)
        # The real request layer substitutes variables in the body just before sending
        # (New-GraphPOSTRequest.ps1:40) - mirrored here so what "Graph" sees is faithful.
        $body = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $body -EscapeForJson
        $script:GraphWrites.Add(@{ Uri = $uri; Type = $type; Body = $body })
        if ($uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations') {
            $Parsed = $body | ConvertFrom-Json
            return [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; displayName = $Parsed.displayName }
        }
        return [pscustomobject]@{ id = 'created-policy-id' }
    }
    function New-GraphGETRequest {
        [CmdletBinding()] param($uri, $tenantid, $asApp, [switch]$ComplexFilter)
        if ($uri -match 'namedLocations/(?<id>[^/?]+)$') {
            return [pscustomobject]@{ id = $Matches.id }
        }
        throw "Unexpected live Graph GET in test: $uri"
    }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $asapp) @() }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $TenantFilter, $Headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTable { [CmdletBinding()] param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($filter) @() }
    function Start-Sleep { [CmdletBinding()] param($Seconds) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPCAPolicy.ps1')

    $script:TemplateJSON = @'
{
  "displayName": "TESTING_CA000-Global-Baseline-Require MFA for All Users",
  "state": "disabled",
  "conditions": {
    "users": { "includeUsers": [ "All" ] },
    "applications": { "includeApplications": [ "All" ] },
    "clientAppTypes": [ "all" ],
    "locations": {
      "includeLocations": [ "All" ],
      "excludeLocations": [ "%CA000_Location_Exclusion_DisplayName%" ]
    }
  },
  "grantControls": { "operator": "OR", "builtInControls": [ "mfa" ] },
  "LocationInfo": [
    {
      "@odata.type": "#microsoft.graph.ipNamedLocation",
      "displayName": "%CA000_Location_Exclusion_DisplayName%",
      "isTrusted": false,
      "ipRanges": [
        { "@odata.type": "#microsoft.graph.iPv4CidrRange", "cidrAddress": "%CA000_Location_Exclusion_IP%" }
      ]
    }
  ],
  "GUID": "d4a3ad81-26df-49f9-83a1-5807b32d11a8",
  "isSynced": false
}
'@

    function Invoke-Deploy ($Locations) {
        $script:GraphWrites = [System.Collections.Generic.List[object]]::new()
        $null = New-CIPPCAPolicy -RawJSON $script:TemplateJSON -TenantFilter 'customer.example.ch' `
            -State 'disabled' -Overwrite $true -ReplacePattern 'none' `
            -PreloadedCAPolicies @([pscustomobject]@{ id = 'other-id'; displayName = 'Unrelated policy' }) `
            -PreloadedLocations $Locations
        $PolicyWrite = $script:GraphWrites | Where-Object { $_.Uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' } | Select-Object -Last 1
        return @{ Writes = $script:GraphWrites; PolicyBody = ($PolicyWrite.Body | ConvertFrom-Json) }
    }
}

Describe 'New-CIPPCAPolicy with custom variables in the named-location path' {

    Context 'the resolved location already exists in the tenant' {
        BeforeAll {
            $script:Existing = [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'SLY_Lupfig-03' }
            $script:Result = Invoke-Deploy @($script:Existing)
        }

        It 'does not create a duplicate named location' {
            $Creates = @($script:Result.Writes | Where-Object {
                    $_.Uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -and $_.Type -eq 'POST'
                })
            $Creates.Count | Should -Be 0
        }

        It 'updates the existing location with the resolved variable values' {
            $Patch = @($script:Result.Writes | Where-Object { $_.Uri -match 'namedLocations/11111111' -and $_.Type -eq 'PATCH' })
            $Patch.Count | Should -Be 1
            $PatchBody = $Patch[0].Body | ConvertFrom-Json
            $PatchBody.displayName | Should -Be 'SLY_Lupfig-03'
            $PatchBody.ipRanges[0].cidrAddress | Should -Be '203.0.113.0/24'
        }

        It 'sends the existing location GUID in excludeLocations, not the token or the name' {
            @($script:Result.PolicyBody.conditions.locations.excludeLocations) | Should -Be @('11111111-1111-1111-1111-111111111111')
        }

        It 'leaves no unresolved tokens or helper blocks in the policy body' {
            $Raw = ($script:Result.Writes | Where-Object { $_.Uri -match '/policies$' } | Select-Object -Last 1).Body
            $Raw | Should -Not -Match '%CA000'
            $Raw | Should -Not -Match 'LocationInfo'
        }
    }

    Context 'the resolved location does not exist yet' {
        BeforeAll {
            $script:Result = Invoke-Deploy @([pscustomobject]@{ id = '99999999-9999-9999-9999-999999999999'; displayName = 'SomeOtherLocation' })
        }

        It 'creates the location under its resolved display name' {
            $Creates = @($script:Result.Writes | Where-Object {
                    $_.Uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -and $_.Type -eq 'POST'
                })
            $Creates.Count | Should -Be 1
            ($Creates[0].Body | ConvertFrom-Json).displayName | Should -Be 'SLY_Lupfig-03'
        }

        It 'sends the new location GUID in excludeLocations' {
            @($script:Result.PolicyBody.conditions.locations.excludeLocations) | Should -Be @('22222222-2222-2222-2222-222222222222')
        }
    }
}
