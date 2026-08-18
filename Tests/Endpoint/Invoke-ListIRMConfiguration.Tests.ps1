# Pester tests for Invoke-ListIRMConfiguration
#
# The load-bearing logic here is AdRmsDetected. Purview Message Encryption is not compatible with
# on-premises AD RMS, and Get-IRMConfiguration's only hint is the shape of LicensingLocation: an
# Azure RMS URL means cloud, anything else means the tenant still points at an AD RMS cluster and
# has to be migrated first. A false negative would let CIPP enable message encryption on a tenant
# where it cannot work.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListIRMConfiguration.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListIRMConfiguration.ps1 under Modules/' }

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

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Get-NormalizedError { param($Message) $Message }

    . $FunctionPath

    function New-IRMRequest {
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ListIRMConfiguration' }
            Query  = @{ tenantFilter = 'contoso.com' }
            Body   = $null
        }
    }

    function New-IRMConfig {
        param($LicensingLocation, $AzureRMSLicensingEnabled = $true)
        [pscustomobject]@{
            AzureRMSLicensingEnabled       = $AzureRMSLicensingEnabled
            InternalLicensingEnabled       = $true
            ExternalLicensingEnabled       = $false
            SimplifiedClientAccessEnabled  = $false
            TransportDecryptionSetting     = 'Optional'
            JournalReportDecryptionEnabled = $true
            LicensingLocation              = $LicensingLocation
        }
    }
}

Describe 'Invoke-ListIRMConfiguration' {
    BeforeEach {
        Mock -CommandName Get-NormalizedError -MockWith { $Message }
    }

    Context 'AD RMS detection' {
        It 'does not flag AD RMS for an Azure RMS licensing location' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @('https://5c6bb73b-1234.rms.na.aadrm.com/_wmcs/licensing')
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.AdRmsDetected | Should -BeFalse
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }

        It 'does not flag AD RMS when the licensing location is empty' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -LicensingLocation @() }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.AdRmsDetected | Should -BeFalse
            $Response.Body.LicensingLocation | Should -BeNullOrEmpty
        }

        It 'does not flag AD RMS when the licensing location is null' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -LicensingLocation $null }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.AdRmsDetected | Should -BeFalse
        }

        It 'flags AD RMS for an on-premises licensing location' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @('https://rms.contoso.local/_wmcs/licensing')
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.AdRmsDetected | Should -BeTrue
        }

        It 'flags AD RMS when an on-premises location is mixed in with the Azure RMS one' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @(
                    'https://5c6bb73b-1234.rms.na.aadrm.com/_wmcs/licensing'
                    'https://rms.contoso.local/_wmcs/licensing'
                )
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.AdRmsDetected | Should -BeTrue
            $Response.Body.LicensingLocation.Count | Should -Be 2
        }

        It 'strips empty entries out of the licensing location' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @('https://5c6bb73b.rms.na.aadrm.com/_wmcs/licensing', '', $null)
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            # An empty string would not match the Azure RMS pattern and would fake an AD RMS hit.
            $Response.Body.AdRmsDetected | Should -BeFalse
            $Response.Body.LicensingLocation.Count | Should -Be 1
        }
    }

    Context 'reported state' {
        It 'reports message encryption as enabled when Azure RMS licensing is on' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @() -AzureRMSLicensingEnabled $true
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.MessageEncryptionEnabled | Should -BeTrue
            $Response.Body.TransportDecryptionSetting | Should -Be 'Optional'
        }

        It 'reports message encryption as disabled when Azure RMS licensing is off' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -LicensingLocation @() -AzureRMSLicensingEnabled $false
            }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.Body.MessageEncryptionEnabled | Should -BeFalse
        }

        It 'queries Get-IRMConfiguration against the requested tenant' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -LicensingLocation @() }

            $null = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Get-IRMConfiguration' -and $tenantid -eq 'contoso.com'
            }
        }
    }

    Context 'failures' {
        It 'returns an error status when the Exchange request throws' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'no exchange for you' }

            $Response = Invoke-ListIRMConfiguration -Request (New-IRMRequest)

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body | Should -Be 'no exchange for you'
        }
    }
}
