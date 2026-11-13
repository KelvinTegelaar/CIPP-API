# Pester tests for Invoke-ExecUnassignAPDevice.
# Pins the Graph contract: a bodyless POST to the Autopilot identity's unassignUserFromDevice action,
# and a 500 with the normalized error when Graph refuses.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecUnassignAPDevice.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecUnassignAPDevice.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $script:Request = [pscustomobject]@{
        Params  = @{ CIPPEndpoint = 'ExecUnassignAPDevice' }
        Headers = @{}
        Body    = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            device       = 'ap-guid'
            serialNumber = 'SN-1'
        }
    }
}

Describe 'Invoke-ExecUnassignAPDevice' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'Device not found' } }
    }

    It 'POSTs to unassignUserFromDevice on the Autopilot identity' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-ExecUnassignAPDevice -Request $script:Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike '*unassigned*ap-guid*SN-1*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities/ap-guid/unassignUserFromDevice' -and
            $type -eq 'POST' -and
            $tenantid -eq 'contoso.com'
        }
    }

    It 'returns 500 with the normalized error when Graph fails' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'boom' }

        $Response = Invoke-ExecUnassignAPDevice -Request $script:Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*Could not unassign*Device not found*'
    }
}
