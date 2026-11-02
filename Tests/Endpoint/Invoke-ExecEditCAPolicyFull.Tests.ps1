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

    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp)
        $script:LastPatch = @{ Uri = $uri; Type = $type; Body = $body }
    }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) $Exception }

    . $FunctionPath

    function Invoke-Edit ($PolicyBody) {
        $script:LastPatch = $null
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
        return @{ Response = $Response; Sent = ($script:LastPatch.Body | ConvertFrom-Json) }
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
