# Pester tests for Invoke-ExecPIMRoleAssignment.
#
# The endpoint is the API/MCP-facing gate for PIM assignment changes. These tests pin its input
# contract: every change needs a justification, any schedule-creating action needs an expiration,
# and a request that spells out permanence ('noExpiration', 'permanent', ...) is refused before
# Invoke-CIPPPIMAssignmentAction is ever called.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Roles/Invoke-ExecPIMRoleAssignment.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecPIMRoleAssignment.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Invoke-CIPPPIMAssignmentAction { param($TenantFilter, $Action, $PrincipalId, $RoleDefinitionId, $DirectoryScopeId, $AssignmentType, $Duration, $EndDateTime, $Justification, $TimeZone, $Headers, $APIName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    function New-PimRequest {
        param([hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter     = 'contoso.onmicrosoft.com'
            Action           = 'GrantActive'
            PrincipalId      = 'user-guid'
            RoleDefinitionId = '62e90394-69f5-4237-9190-012177145e10'
            DirectoryScopeId = '/'
            AssignmentType   = 'Eligible'
            Duration         = 'PT4H'
            Justification    = 'Ticket 42'
        }
        foreach ($Key in $Body.Keys) {
            if ($null -eq $Body[$Key]) { $RequestBody.PSObject.Properties.Remove($Key) }
            else { $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force }
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecPIMRoleAssignment' }
        }
    }
}

Describe 'Invoke-ExecPIMRoleAssignment' {
    BeforeEach {
        Mock Invoke-CIPPPIMAssignmentAction { [pscustomobject]@{ resultText = 'done'; state = 'success' } }
        Mock Write-LogMessage {}
    }

    Context 'time zone for the result wording' {
        It 'passes the browser time zone through, and leaves it out when the request has none' {
            $null = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest -Body @{ TimeZone = 'Australia/Perth' }) -TriggerMetadata $null
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { $TimeZone -eq 'Australia/Perth' -and $Duration -eq 'PT4H' }
            $null = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest) -TriggerMetadata $null
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($TimeZone) }
        }
    }

    Context 'input validation (nothing reaches PIM)' {
        It 'returns 400 when required fields are missing' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ PrincipalId = $null })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'required'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'returns 400 for an unknown action' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Action = 'MakePermanent' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'not supported'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'returns 400 without a justification' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Justification = '' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'justification'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'refuses a duration that asks for permanence: <_>' -ForEach @('noExpiration', 'permanent', 'never', 'unlimited') {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Duration = $_ })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'Permanent \(no-expiration\) assignments cannot be created'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'refuses an end date that asks for permanence' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Duration = $null; EndDateTime = 'noExpiration' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'requires an expiration for <_>' -ForEach @('GrantActive', 'Extend', 'Renew') {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Action = $_; Duration = $null })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'requires a Duration or an EndDateTime'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 0 -Exactly
        }

        It 'rejects Duration and EndDateTime together' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ EndDateTime = '2099-01-01T00:00:00Z' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'not both'
        }

        It 'rejects an unparseable end date' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Duration = $null; EndDateTime = 'next tuesday' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].resultText | Should -Match 'not a valid date'
        }
    }

    Context 'forwarding to Invoke-CIPPPIMAssignmentAction' {
        It 'passes the duration, scope, type and justification through' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest)
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results[0].state | Should -Be 'success'
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter {
                $Action -eq 'GrantActive' -and $Duration -eq 'PT4H' -and $DirectoryScopeId -eq '/' -and $AssignmentType -eq 'Eligible' -and $Justification -eq 'Ticket 42' -and $null -eq $EndDateTime
            }
        }

        It 'converts a unix-seconds end date to a UTC datetime' {
            $Unix = [System.DateTimeOffset]::UtcNow.AddHours(6).ToUnixTimeSeconds()
            $null = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Duration = $null; EndDateTime = $Unix })
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter {
                $EndDateTime -is [datetime] -and [math]::Abs(($EndDateTime - [datetime]::UtcNow).TotalHours - 6) -lt 0.1
            }
        }

        It 'unwraps label/value objects from the dialog' {
            $Request = New-PimRequest @{
                Action   = [pscustomobject]@{ label = 'Convert to eligible'; value = 'ConvertToEligible' }
                Duration = [pscustomobject]@{ label = '1 year'; value = 'P365D' }
            }
            $null = Invoke-ExecPIMRoleAssignment -Request $Request
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { $Action -eq 'ConvertToEligible' -and $Duration -eq 'P365D' }
        }

        It 'lets Remove through without an expiration' {
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Action = 'Remove'; Duration = $null })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke Invoke-CIPPPIMAssignmentAction -Times 1 -Exactly -ParameterFilter { $Action -eq 'Remove' }
        }

        It 'returns 400 with the refusal message when the action throws' {
            Mock Invoke-CIPPPIMAssignmentAction { throw 'Refusing: last active Global Administrator' }
            $Response = Invoke-ExecPIMRoleAssignment -Request (New-PimRequest @{ Action = 'Remove'; Duration = $null })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results[0].state | Should -Be 'error'
            $Response.Body.Results[0].resultText | Should -Match 'last active Global Administrator'
        }
    }
}
