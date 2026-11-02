# Pester tests for Invoke-EditContact
#
# Regression coverage for the split-address bug: editing a mail contact's email used to set only
# WindowsEmailAddress (via Set-Contact), which updates the displayed 'mail' attribute but NOT the
# ExternalEmailAddress routing target. The contact then showed the new address while mail kept
# delivering to the old one. Both writes must happen, and the Set-MailContact routing update must
# be the last one to land.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-EditContact.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-EditContact.ps1 under Modules/' }

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

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-ContactRequest {
        param([hashtable]$Body = @{})

        $Defaults = @{
            tenantID    = 'contoso.com'
            ContactID   = 'contact-guid-1'
            displayName = 'SEQ IT Support'
            email       = 'techteam@seqit.com.au'
        }
        foreach ($Key in $Body.Keys) { $Defaults[$Key] = $Body[$Key] }

        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'EditContact' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Defaults
        }
    }
}

Describe 'Invoke-EditContact' {
    BeforeEach {
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'boom' } }
    }

    Context 'email address routing' {
        It 'sets ExternalEmailAddress on Set-MailContact so mail actually reroutes' {
            $null = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-MailContact' -and $cmdParams.ExternalEmailAddress -eq 'techteam@seqit.com.au'
            }
        }

        It 'still sets WindowsEmailAddress on Set-Contact so the displayed address matches' {
            $null = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-Contact' -and $cmdParams.WindowsEmailAddress -eq 'techteam@seqit.com.au'
            }
        }

        It 'applies the routing update last so Set-Contact cannot clobber it' {
            $script:CmdletOrder = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName New-ExoRequest -MockWith { $script:CmdletOrder.Add($cmdlet) }

            $null = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            $script:CmdletOrder | Should -Be @('Set-Contact', 'Set-MailContact')
        }

        It 'targets both cmdlets at the same contact identity' {
            $null = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 2 -Exactly -ParameterFilter {
                $cmdParams.Identity -eq 'contact-guid-1'
            }
        }

        It 'omits ExternalEmailAddress when no email was submitted' {
            $null = Invoke-EditContact -Request (New-ContactRequest -Body @{ email = ''; mailTip = 'tip' }) -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-MailContact' -and $cmdParams.ContainsKey('ExternalEmailAddress')
            }
        }

        It 'issues no Set-MailContact call at all when only Set-Contact fields changed' {
            $null = Invoke-EditContact -Request (New-ContactRequest -Body @{ email = '' }) -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-MailContact' }
        }
    }

    Context 'response contract' {
        It 'returns OK and a Results string on success' {
            $Response = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results | Should -Match 'Successfully edited contact SEQ IT Support'
        }

        It 'returns InternalServerError and surfaces the normalized error on failure' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'EXO exploded' }

            $Response = Invoke-EditContact -Request (New-ContactRequest) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results | Should -Match 'Failed to edit contact. boom'
        }
    }
}
