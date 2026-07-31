# Pester tests for Invoke-ExecSetDefaultMFAMethod input validation and Graph PATCH shape.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetDefaultMFAMethod.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }

    function New-TestRequest {
        param($MethodType, $UserId = 'user@contoso.com', $TenantFilter = 'contoso.com')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSetDefaultMFAMethod' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{
                tenantFilter = $TenantFilter
                ID           = $UserId
                MethodType   = $MethodType
            }
        }
    }

    . $FunctionPath
}

Describe 'Invoke-ExecSetDefaultMFAMethod' {
    BeforeEach {
        $script:patchUri = $null
        $script:patchBody = $null
        $script:patchType = $null

        Mock -CommandName New-GraphPOSTRequest -MockWith {
            $script:patchUri = $uri
            $script:patchBody = $body
            $script:patchType = $type
        }
        Mock -CommandName Write-LogMessage -MockWith {}
    }

    It 'patches signInPreferences on beta with the selected method' {
        $response = Invoke-ExecSetDefaultMFAMethod -Request (New-TestRequest -MethodType 'oath') -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:patchType | Should -Be 'PATCH'
        $script:patchUri | Should -Be 'https://graph.microsoft.com/beta/users/user%40contoso.com/authentication/signInPreferences'
        ($script:patchBody | ConvertFrom-Json).userPreferredMethodForSecondaryAuthentication | Should -Be 'oath'
    }

    It 'encodes a guest UPN so the #EXT# fragment does not truncate the Graph path' {
        $Request = New-TestRequest -MethodType 'push' -UserId 'alice_fabrikam.com#EXT#@contoso.onmicrosoft.com'

        $null = Invoke-ExecSetDefaultMFAMethod -Request $Request -TriggerMetadata $null

        $script:patchUri | Should -Be 'https://graph.microsoft.com/beta/users/alice_fabrikam.com%23EXT%23%40contoso.onmicrosoft.com/authentication/signInPreferences'
        $script:patchUri | Should -Not -Match '#'
    }

    It 'unwraps the autoComplete {label,value} shape from the frontend' {
        $Request = New-TestRequest -MethodType ([pscustomobject]@{ label = 'SMS'; value = 'sms' })

        $null = Invoke-ExecSetDefaultMFAMethod -Request $Request -TriggerMetadata $null

        ($script:patchBody | ConvertFrom-Json).userPreferredMethodForSecondaryAuthentication | Should -Be 'sms'
    }

    It 'rejects a method type Graph does not accept' {
        $response = Invoke-ExecSetDefaultMFAMethod -Request (New-TestRequest -MethodType 'fido2') -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $script:patchUri | Should -BeNullOrEmpty
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'rejects a request with no method type' {
        $response = Invoke-ExecSetDefaultMFAMethod -Request (New-TestRequest -MethodType $null) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}
