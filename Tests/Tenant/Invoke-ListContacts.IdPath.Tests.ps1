# The module is compiled without the function file's `using namespace`, so a short [List[...]]
# only fails at runtime on the single-contact path. This file has no `using namespace` either.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Administration/Contacts/Invoke-ListContacts.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-EXORequest { param($tenantid, $cmdlet, $cmdParams) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-NormalizedError { param($Message) $Message }

    . $FunctionPath
}

Describe 'Invoke-ListContacts single-contact path' {
    BeforeEach {
        Mock -CommandName New-EXORequest -MockWith { $null }
        Mock -CommandName New-EXORequest -ParameterFilter { $cmdlet -eq 'Get-Contact' } -MockWith {
            [pscustomobject]@{ Id = 'c1'; DisplayName = 'Jo'; Phone = '1'; MobilePhone = '2' }
        }
        Mock -CommandName New-EXORequest -ParameterFilter { $cmdlet -eq 'Get-MailContact' } -MockWith {
            [pscustomobject]@{ ExternalEmailAddress = 'SMTP:jo@example.com' }
        }
    }

    It 'returns the contact with its phones instead of a type error' {
        $Request = [pscustomobject]@{ Query = @{ tenantFilter = 't'; id = 'c1' } }
        $Result = Invoke-ListContacts -Request $Request
        $Result.StatusCode | Should -Be 200
        $Result.Body.mail | Should -Be 'jo@example.com'
        @($Result.Body.phones).Count | Should -Be 2
    }
}
