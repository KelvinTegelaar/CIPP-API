# Pester tests for Invoke-ExecSetSecurityIncident
# Validates the PATCH body built for severity changes and resolving comments,
# and that free-text comments produce valid JSON (regression for the body builder).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Invoke-ExecSetSecurityIncident.ps1'

    # The Functions worker exposes [HttpStatusCode] as an accelerator; register it for tests.
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $type, $tenantid, $body, $asApp) $script:lastPatch = @{ Uri = $uri; Type = $type; Tenant = $tenantid; Body = $body } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) $script:logs += $message }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath
}

Describe 'Invoke-ExecSetSecurityIncident' {
    BeforeEach {
        $script:lastPatch = $null
        $script:logs = @()
    }

    It 'sends only the chosen severity, leaving the assignee untouched' {
        # The severity action omits Assigned, so no assignedTo should be written.
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecSetSecurityIncident' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                GUID         = 'incident-1'
                Severity     = [pscustomobject]@{ value = 'high'; label = 'High' }
            }
        }

        $response = Invoke-ExecSetSecurityIncident -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $lastPatch.Type | Should -Be 'PATCH'
        $lastPatch.Uri | Should -Match '/security/incidents/incident-1'
        $parsed = $lastPatch.Body | ConvertFrom-Json
        $parsed.severity | Should -Be 'high'
        $parsed.PSObject.Properties.Name | Should -Not -Contain 'assignedTo'
    }

    It 'assigns to the calling user when the AssignToSelf flag is set' {
        $principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"caller@contoso.com"}'))
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecSetSecurityIncident' }
            Headers = @{ 'x-ms-client-principal' = $principal }
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                GUID         = 'incident-1'
                AssignToSelf = $true
            }
        }

        $response = Invoke-ExecSetSecurityIncident -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        ($lastPatch.Body | ConvertFrom-Json).assignedTo | Should -Be 'caller@contoso.com'
    }

    It 'sends status resolved together with the resolving comment' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecSetSecurityIncident' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                GUID         = 'incident-2'
                Status       = 'resolved'
                Comment      = 'Closed after review'
            }
        }

        $response = Invoke-ExecSetSecurityIncident -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $parsed = $lastPatch.Body | ConvertFrom-Json
        $parsed.status | Should -Be 'resolved'
        $parsed.resolvingComment | Should -Be 'Closed after review'
    }

    It 'produces valid JSON when the comment contains quotes and newlines' {
        $comment = "Line one with a `"quote`"`nLine two with a backslash \"
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecSetSecurityIncident' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                GUID         = 'incident-3'
                Status       = 'resolved'
                Comment      = $comment
            }
        }

        $response = Invoke-ExecSetSecurityIncident -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        { $lastPatch.Body | ConvertFrom-Json } | Should -Not -Throw
        ($lastPatch.Body | ConvertFrom-Json).resolvingComment | Should -Be $comment
    }

    It 'refuses to update a redirected incident' {
        $request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecSetSecurityIncident' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                GUID         = 'incident-4'
                Status       = 'resolved'
                Redirected   = 1
            }
        }

        $response = Invoke-ExecSetSecurityIncident -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'Refused to update'
        $lastPatch | Should -BeNullOrEmpty
    }
}
