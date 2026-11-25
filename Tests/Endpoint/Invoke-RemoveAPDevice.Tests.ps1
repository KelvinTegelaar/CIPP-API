# Without a tenant the delete would run against the partner tenant's own Autopilot devices.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-RemoveAPDevice.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Invoke-RemoveAPDevice' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'refuses a request without a tenant and calls nothing' -ForEach @(@{ Tenant = $null }, @{ Tenant = 'null' }) {
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'RemoveAPDevice' }; Headers = @{}; Query = @{}; Body = [pscustomobject]@{ ID = 'ap-guid'; tenantFilter = $Tenant } }
        $Response = Invoke-RemoveAPDevice -Request $Request

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'deletes the device in the named tenant' {
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'RemoveAPDevice' }; Headers = @{}; Query = @{}; Body = [pscustomobject]@{ ID = 'ap-guid'; tenantFilter = 'contoso.com' } }
        $Response = Invoke-RemoveAPDevice -Request $Request

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $tenantid -eq 'contoso.com' -and $uri -like '*/windowsAutopilotDeviceIdentities/ap-guid' }
    }
}
