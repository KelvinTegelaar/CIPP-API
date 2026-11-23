BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    $FunctionPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-ExecSetDeviceExtensionAttribute.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $Modules 'CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . $FunctionPath

    function Invoke-Set {
        param([hashtable]$Body)
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSetDeviceExtensionAttribute' }; Headers = @{}; Body = [pscustomobject]$Body }
        Invoke-ExecSetDeviceExtensionAttribute -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-ExecSetDeviceExtensionAttribute' {
    BeforeEach {
        $script:Posted = $null
        Mock New-GraphPOSTRequest { $script:Posted = $body }
    }

    It 'sets the chosen attribute with a PATCH to the device' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'dev1'; Attribute = @{ label = 'Extension attribute 7'; value = 7 }; Value = ' Kiosk ' }

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be "Set extension attribute 7 to 'Kiosk'"
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/beta/devices/dev1' -and $type -eq 'PATCH' -and $tenantid -eq 'contoso.com'
        }
        $script:Posted | Should -Be '{"extensionAttributes":{"extensionAttribute7":"Kiosk"}}'
    }

    It 'clears the attribute with null when the value is <Case>' -ForEach @(
        @{ Case = 'empty'; Value = '' }
        @{ Case = 'blank'; Value = '   ' }
        @{ Case = 'missing'; Value = $null }
    ) {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'dev1'; Attribute = '15'; Value = $Value }

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Cleared extension attribute 15'
        $script:Posted | Should -Be '{"extensionAttributes":{"extensionAttribute15":null}}'
    }

    It 'rejects attribute <Attribute>' -ForEach @(
        @{ Attribute = 0 }
        @{ Attribute = 16 }
        @{ Attribute = '1.5' }
        @{ Attribute = 'abc' }
        @{ Attribute = $null }
    ) {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'dev1'; Attribute = $Attribute; Value = 'x' }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'rejects a request with no device' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; Attribute = 1; Value = 'x' }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'returns the Graph error with a failure status' {
        Mock New-GraphPOSTRequest { throw 'Insufficient privileges' }

        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'dev1'; Attribute = 1; Value = 'x' }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*Insufficient privileges*'
    }
}
