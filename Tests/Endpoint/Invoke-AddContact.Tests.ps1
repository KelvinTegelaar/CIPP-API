# Pester tests for Invoke-AddContact
#
# hidefromGAL used to be read with [bool], and [bool]'false' is $true in PowerShell. Any client that
# sends the flag as text (CSV imports, the API module, raw REST calls) therefore hid every contact from
# the Global Address List. The flag has to be interpreted as text so 'false' means false.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddContact.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddContact.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Start-Sleep { param($Milliseconds, $Seconds) }

    . $FunctionPath

    function New-ContactRequest {
        param([hashtable]$Body = @{})

        $Defaults = @{
            tenantID    = 'contoso.com'
            displayName = 'Supplier Helpdesk'
            email       = 'help@supplier.example'
        }
        foreach ($Key in $Body.Keys) { $Defaults[$Key] = $Body[$Key] }

        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddContact' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Defaults
        }
    }
}

Describe 'Invoke-AddContact' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith {
            if ($cmdlet -eq 'New-MailContact') { @{ id = 'contact-guid-1' } }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'boom' } }
    }

    Context 'hidefromGAL interpretation' {
        It 'does not hide the contact when hidefromGAL is the string "false"' {
            $null = Invoke-AddContact -Request (New-ContactRequest @{ hidefromGAL = 'false' })
            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-MailContact' }
        }

        It 'does not hide the contact when hidefromGAL is boolean $false or absent' {
            $null = Invoke-AddContact -Request (New-ContactRequest @{ hidefromGAL = $false })
            $null = Invoke-AddContact -Request (New-ContactRequest)
            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-MailContact' }
        }

        It 'hides the contact when hidefromGAL is boolean $true' {
            $null = Invoke-AddContact -Request (New-ContactRequest @{ hidefromGAL = $true })
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-MailContact' -and $cmdParams.HiddenFromAddressListsEnabled -eq $true
            }
        }

        It 'hides the contact when hidefromGAL is the string "true" in any casing' {
            $null = Invoke-AddContact -Request (New-ContactRequest @{ hidefromGAL = 'True' })
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-MailContact' -and $cmdParams.HiddenFromAddressListsEnabled -eq $true
            }
        }
    }

    Context 'response' {
        It 'returns OK and a Results string on success' {
            $Response = Invoke-AddContact -Request (New-ContactRequest)
            $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
            $Response.Body.Results | Should -Match 'Successfully created contact Supplier Helpdesk'
        }
    }
}
