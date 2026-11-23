# Pester tests for Invoke-ExecEditCAPolicyFull
# The save is a PATCH, so what the body leaves out keeps whatever the tenant policy already had.
# These pin the two halves of that: emptied collections go out as [], and a condition block the
# editor emptied goes out as null rather than being dropped or sent half-populated.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecEditCAPolicyFull.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecEditCAPolicyFull.ps1 under Modules/' }

    # The Functions worker exposes [HttpStatusCode] as an accelerator; register it for tests.
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    # The canonicalizer is the real one - that is the behaviour under test.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')
    # So is the name resolution, against a stub tenant below.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAUserNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAGroupNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Resolve-CIPPCAPolicyNames.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:LocationId = '11111111-1111-1111-1111-111111111111'
    $script:GroupId = '22222222-2222-2222-2222-222222222222'
    function New-GraphGETRequest {
        [CmdletBinding()] param($uri, $tenantid, $asApp)
        $script:TenantLookups++
        @([pscustomobject]@{ id = $script:LocationId; displayName = 'CT-CA-Anthropic' })
    }
    function New-GraphBulkRequest {
        [CmdletBinding()] param($Requests, $tenantid, $asapp)
        $script:TenantLookups++
        foreach ($Request in $Requests) {
            $Found = if ($Request.url -like "groups?*$([System.Uri]::EscapeDataString("'CA-Exclude'"))*") { @([pscustomobject]@{ id = $script:GroupId; displayName = 'CA-Exclude' }) }
            elseif ($Request.url -like "groups?*$([System.Uri]::EscapeDataString("'Shared'"))*") { @([pscustomobject]@{ id = $script:GroupId; displayName = 'Shared' }, [pscustomobject]@{ id = '99999999-9999-9999-9999-999999999999'; displayName = 'Shared' }) }
            else { @() }
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = $Found } }
        }
    }
    # The tenant's custom variables, substituted the way Get-CIPPTextReplacement does.
    function Get-CIPPTextReplacement {
        [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson)
        $Text -replace '%OfficeLocation%', 'CT-CA-Anthropic' -replace '%ExcludeGroup%', 'CA-Exclude'
    }

    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp)
        $script:LastPatch = @{ Uri = $uri; Type = $type; Body = $body }
    }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    function Invoke-Edit ($PolicyBody) {
        $script:LastPatch = $null
        $script:TenantLookups = 0
        $Request = @{
            Params  = @{ CIPPEndpoint = 'ExecEditCAPolicyFull' }
            Headers = @{}
            Query   = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                PolicyId     = 'policy-guid'
                PolicyBody   = ($PolicyBody | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
            }
        }
        $Response = Invoke-ExecEditCAPolicyFull -Request $Request
        return @{ Response = $Response; Sent = ($script:LastPatch ? ($script:LastPatch.Body | ConvertFrom-Json) : $null) }
    }
}

Describe 'Invoke-ExecEditCAPolicyFull' {

    Context 'a policy whose blocks the editor emptied' {
        BeforeAll {
            $script:Result = Invoke-Edit @{
                displayName     = 'CA201'
                state           = 'disabled'
                conditions      = @{
                    clientAppTypes = @('all')
                    applications   = @{ includeApplications = @('All'); excludeApplications = @() }
                    users          = @{ includeUsers = @('All'); includeGroups = @(); excludeGroups = @() }
                    platforms      = $null
                    devices        = $null
                }
                grantControls   = @{ operator = 'OR'; builtInControls = @('mfa') }
                sessionControls = $null
            }
            $script:Sent = $script:Result.Sent
        }

        It 'returns OK' {
            $script:Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }

        It 'PATCHes the policy by id' {
            $script:LastPatch.Type | Should -Be 'PATCH'
            $script:LastPatch.Uri | Should -Be 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies/policy-guid'
        }

        It 'sends the emptied collections as [] so Graph clears them' {
            $script:LastPatch.Body | Should -Match '"includeGroups":\[\]'
            $script:LastPatch.Body | Should -Match '"excludeApplications":\[\]'
        }

        It 'restores collections the body omitted as [] - a partial body must still clear them' {
            # The form never sent excludeUsers at all; the canonicalizer says its absence out loud.
            $script:LastPatch.Body | Should -Match '"excludeUsers":\[\]'
            $script:Sent.conditions.users.PSObject.Properties.Name | Should -Contain 'excludeRoles'
        }

        It 'sends the emptied <Block> block as null rather than dropping it' -ForEach @(
            @{ Block = 'platforms' }
            @{ Block = 'devices' }
        ) {
            $script:Sent.conditions.PSObject.Properties.Name | Should -Contain $Block
            $script:Sent.conditions.$Block | Should -BeNullOrEmpty
        }

        It 'sends sessionControls as null rather than dropping it' {
            $script:Sent.PSObject.Properties.Name | Should -Contain 'sessionControls'
            $script:Sent.sessionControls | Should -BeNullOrEmpty
        }

        It 'leaves the assignments the user kept alone' {
            $script:Sent.conditions.users.includeUsers | Should -Be @('All')
            $script:Sent.grantControls.builtInControls | Should -Be @('mfa')
            $script:Sent.displayName | Should -Be 'CA201'
        }
    }

    Context 'a half-populated block that Graph would reject' {
        It 'collapses platforms with no includePlatforms to null' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All') }
                    platforms = @{ includePlatforms = @(); excludePlatforms = @() }
                }
            }
            $Result.Sent.conditions.platforms | Should -BeNullOrEmpty
        }

        It 'keeps a platforms block that names a platform' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All') }
                    platforms = @{ includePlatforms = @('android'); excludePlatforms = @() }
                }
            }
            $Result.Sent.conditions.platforms.includePlatforms | Should -Be @('android')
        }
    }

    Context 'read-only properties' {
        It 'never PATCHes id or createdDateTime back to Graph' {
            $Result = Invoke-Edit @{
                displayName     = 'CA201'
                id              = 'policy-guid'
                createdDateTime = '2026-01-01T00:00:00Z'
                templateId      = 'template-guid'
                conditions      = @{ users = @{ includeUsers = @('All') } }
            }
            $Names = $Result.Sent.PSObject.Properties.Name
            $Names | Should -Not -Contain 'id'
            $Names | Should -Not -Contain 'createdDateTime'
            $Names | Should -Not -Contain 'templateId'
        }
    }

    Context 'display names in the body' {
        It 'sends the id of a named location added by name' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All') }
                    locations = @{ includeLocations = @('All'); excludeLocations = @('AllTrusted', 'CT-CA-Anthropic') }
                }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Result.Sent.conditions.locations.excludeLocations) | Should -Be @('AllTrusted', $script:LocationId)
            $script:LastPatch.Body | Should -Not -Match 'CT-CA-Anthropic'
        }

        It 'sends the id of a group added by name' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{ users = @{ includeUsers = @('All'); excludeGroups = @('CA-Exclude') } }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Result.Sent.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
        }

        It 'does not look anything up when the body already holds ids' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All'); excludeGroups = @($script:GroupId) }
                    locations = @{ includeLocations = @('All'); excludeLocations = @($script:LocationId) }
                }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $script:TenantLookups | Should -Be 0
        }

        It 'returns 404 naming a location the tenant does not have, and does not PATCH' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All') }
                    locations = @{ includeLocations = @('All'); excludeLocations = @('Nowhere') }
                }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
            $Result.Response.Body.Results | Should -BeLike "Failed to update CA policy policy-guid for contoso.onmicrosoft.com: *Named location 'Nowhere'*not found*"
            $script:LastPatch | Should -BeNullOrEmpty
        }

        It 'returns 404 naming a group the tenant does not have, and does not PATCH' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{ users = @{ includeUsers = @('All'); excludeGroups = @('No Such Group') } }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
            $Result.Response.Body.Results | Should -BeLike "*Group 'No Such Group' not found*"
            $script:LastPatch | Should -BeNullOrEmpty
        }

        It 'returns 400 for a group name two groups share, and does not PATCH' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{ users = @{ includeUsers = @('All'); excludeGroups = @('Shared') } }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Result.Response.Body.Results | Should -BeLike "*Group 'Shared' matches 2 groups*"
            $script:LastPatch | Should -BeNullOrEmpty
        }
    }

    Context '%variables% in the body' {
        It 'fills in a variable location and group before resolving them to ids' {
            $Result = Invoke-Edit @{
                displayName = 'CA201'
                conditions  = @{
                    users     = @{ includeUsers = @('All'); excludeGroups = @('%ExcludeGroup%') }
                    locations = @{ includeLocations = @('All'); excludeLocations = @('%OfficeLocation%') }
                }
            }
            $Result.Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Result.Sent.conditions.locations.excludeLocations) | Should -Be @($script:LocationId)
            @($Result.Sent.conditions.users.excludeGroups) | Should -Be @($script:GroupId)
        }
    }

    Context 'validation' {
        It 'rejects a request with no PolicyBody' {
            $Request = @{
                Params  = @{ CIPPEndpoint = 'ExecEditCAPolicyFull' }
                Headers = @{}
                Query   = @{}
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; PolicyId = 'policy-guid' }
            }
            (Invoke-ExecEditCAPolicyFull -Request $Request).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }

        It 'rejects a request with no PolicyId' {
            $Request = @{
                Params  = @{ CIPPEndpoint = 'ExecEditCAPolicyFull' }
                Headers = @{}
                Query   = @{}
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; PolicyBody = [pscustomobject]@{ displayName = 'CA201' } }
            }
            (Invoke-ExecEditCAPolicyFull -Request $Request).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }
    }
}
