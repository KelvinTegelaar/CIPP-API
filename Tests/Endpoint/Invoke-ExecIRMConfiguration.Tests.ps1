# Pester tests for Invoke-ExecIRMConfiguration
#
# The 'Set' action forwards caller-supplied settings to Set-IRMConfiguration. Two things must hold:
# only the keys the caller actually sent reach Exchange (an API client posting one switch must not
# flip the others), and only whitelisted keys/values get through, because the body is caller
# controlled and lands on a tenant-wide cmdlet.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecIRMConfiguration.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecIRMConfiguration.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The function uses the short [HttpStatusCode] (the Functions host supplies `using namespace
    # System.Net`). Register a type accelerator so it resolves when the function is dot-sourced here.
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { [CmdletBinding()] param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . $FunctionPath

    function New-SetRequest {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecIRMConfiguration' }
            Headers = @{}
            Query   = @{}
            Body    = [pscustomobject](@{ tenantFilter = 'contoso.com'; Action = 'Set' } + $Body)
        }
    }
}

Describe 'Invoke-ExecIRMConfiguration' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
    }

    Context 'Set' {
        It 'forwards every supported setting when the tools page posts the full form' {
            $Response = Invoke-ExecIRMConfiguration -Request (New-SetRequest @{
                    AzureRMSLicensingEnabled                   = $true
                    SimplifiedClientAccessEnabled              = $true
                    EnablePdfEncryption                        = $true
                    DecryptAttachmentForEncryptOnly            = $false
                    SimplifiedClientAccessDoNotForwardDisabled = $false
                    SimplifiedClientAccessEncryptOnlyDisabled  = $false
                    TransportDecryptionSetting                 = 'Mandatory'
                })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $tenantid -eq 'contoso.com' -and
                $cmdParams.Count -eq 7 -and
                $cmdParams.EnablePdfEncryption -eq $true -and
                $cmdParams.DecryptAttachmentForEncryptOnly -eq $false -and
                $cmdParams.TransportDecryptionSetting -eq 'Mandatory'
            }
            $Response.Body.Results | Should -Match 'EnablePdfEncryption = True'
        }

        It 'only touches the settings the caller sent' {
            $null = Invoke-ExecIRMConfiguration -Request (New-SetRequest @{ EnablePdfEncryption = 'true' })

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdParams.Count -eq 1 -and $cmdParams.EnablePdfEncryption -eq $true
            }
        }

        It 'drops an unknown transport decryption value instead of forwarding it' {
            $null = Invoke-ExecIRMConfiguration -Request (New-SetRequest @{
                    AzureRMSLicensingEnabled   = $true
                    TransportDecryptionSetting = 'Sometimes'
                })

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdParams.Count -eq 1 -and -not $cmdParams.ContainsKey('TransportDecryptionSetting')
            }
        }

        It 'fails when no supported setting was provided' {
            $Response = Invoke-ExecIRMConfiguration -Request (New-SetRequest @{ SearchEnabled = $false })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results | Should -Match 'No message encryption settings'
            Should -Invoke New-ExoRequest -Times 0 -Exactly
        }
    }

    Context 'Test' {
        It 'refuses to run without both addresses' {
            $Request = New-SetRequest @{ Sender = 'a@contoso.com' }
            $Request.Body.Action = 'Test'

            $Response = Invoke-ExecIRMConfiguration -Request $Request

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            Should -Invoke New-ExoRequest -Times 0 -Exactly
        }
    }
}
