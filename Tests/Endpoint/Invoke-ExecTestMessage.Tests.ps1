# Pester tests for Invoke-ExecTestMessage.
#
# Pins the Test-Message call shape: an uploaded .eml goes to Exchange byte-for-byte, a composed
# message is a well-formed RFC 5322 text, recipients arrive as a list, and the report address and
# at least one rule scope are required before anything is sent.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecTestMessage.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function New-CIPPAsyncDeployment { param($Names, $StepTitles, $Source, $TenantFilter) 'job-1' }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Resolve-DnsHttpsQuery { param($Domain, $RecordType) }

    . $FunctionPath

    function New-Request { param($Body) [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecTestMessage' }; Headers = @{}; Body = $Body } }
}

Describe 'Invoke-ExecTestMessage' {
    BeforeEach {
        Mock New-ExoRequest { $null }
        Mock Write-LogMessage { }
        Mock Set-CIPPAsyncDeploymentStep { }
        Mock Set-CIPPAsyncDeploymentStatus { }
        Mock Start-CIPPOrchestrator { }
        # Every external domain receives mail unless a test says otherwise.
        Mock Resolve-DnsHttpsQuery { [pscustomobject]@{ Status = 0; Answer = @([pscustomobject]@{ type = 15; data = '10 mx.example.' }) } }
    }

    It 'sends an uploaded .eml to Exchange unchanged with the recipients as a list' {
        $Eml = "From: a@x.example`r`nTo: b@y.example`r`nSubject: hi`r`n`r`nbody"
        $Response = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'; Sender = 'a@x.example'; Recipients = 'b@y.example, c@y.example'
                    SendReportTo = 'admin@contoso.onmicrosoft.com'; MessageFileBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Eml))
                }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Test-Message' -and $tenantid -eq 'contoso.onmicrosoft.com' -and
            ([Text.Encoding]::UTF8.GetString($cmdParams.MessageFileData) -eq $Eml) -and
            @($cmdParams.Recipients).Count -eq 2 -and $cmdParams.Recipients[1] -eq 'c@y.example' -and
            $cmdParams.SendReportTo -eq 'admin@contoso.onmicrosoft.com' -and $cmdParams.Sender -eq 'a@x.example' -and
            $cmdParams.TransportRules -eq $true -and -not $cmdParams.ContainsKey('UnifiedDlpRules') -and $cmdParams.Force -eq $true
        }
        $Response.Body.Results | Should -Match 'admin@contoso.onmicrosoft.com'
        # The frontend finds the dropped message in the trace by these
        $Response.Body.Subject | Should -Be 'hi'
        $Response.Body.DeploymentId | Should -Be 'job-1'
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter {
            $Batch = @($InputObject.Batch)[0]
            $Batch.FunctionName -eq 'ExecTestMessageTrace' -and $Batch.DeploymentId -eq 'job-1' -and $Batch.Recipient -eq 'b@y.example' -and $Batch.Subject -eq 'hi'
        }
        $Response.Body.Sender | Should -Be 'a@x.example'
        @($Response.Body.Recipients).Count | Should -Be 2
        { [datetime]$Response.Body.SubmittedUtc } | Should -Not -Throw
    }

    It 'composes a well-formed message from subject and body when no .eml is given' {
        $Response = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'; Sender = 'a@x.example'; Recipients = @('b@y.example')
                    SendReportTo = 'admin@contoso.onmicrosoft.com'; Subject = 'Invoice 42'; Body = 'please pay'; UnifiedDlpRules = $true
                }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            if ($cmdlet -ne 'Test-Message') { return $false }
            $Text = [Text.Encoding]::UTF8.GetString($cmdParams.MessageFileData)
            $Text -match "^From: a@x\.example`r`nTo: b@y\.example`r`nSubject: Invoice 42`r`n" -and $Text -match "`r`n`r`nplease pay$" -and
            $Text -match 'Message-ID: <' -and $cmdParams.UnifiedDlpRules -eq $true -and $cmdParams.TransportRules -eq $true
        }
        $Response.Body.Subject | Should -Be 'Invoice 42'
    }

    It 'refuses to send without a report address or a rule scope' {
        $NoReport = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{ tenantFilter = 't'; Recipients = @('b@y.example') }))
        $NoReport.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        $NoReport.Body.Results | Should -Match 'SendReportTo'
        $NoScope = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{ tenantFilter = 't'; Recipients = @('b@y.example'); SendReportTo = 'a@t'; TransportRules = $false }))
        $NoScope.Body.Results | Should -Match 'mail flow rules, unified DLP rules, or both'
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'treats the admin API result-serialisation defect as submitted but surfaces other errors' {
        Mock New-ExoRequest { throw "Unable to cast object of type 'Microsoft.Exchange.Management.Powershell.Support.TestMessageResult' to type 'System.Collections.IEnumerable'." }
        $Response = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{ tenantFilter = 't'; Sender = 'a@x.example'; Recipients = @('b@y.example'); SendReportTo = 'admin@t' }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Match 'submitted'

        Mock New-ExoRequest { throw 'You must specify a Sender or MessageFileData from which to read the sender.' }
        $Response = Invoke-ExecTestMessage -Request (New-Request ([pscustomobject]@{ tenantFilter = 't'; Recipients = @('b@y.example'); SendReportTo = 'admin@t'; MessageFileBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('x')) }))
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'must specify a Sender'
    }

    Context 'recipient domains that cannot receive mail' {
        BeforeEach {
            $script:Body = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; Sender = 'a@contoso.onmicrosoft.com'; SendReportTo = 'admin@contoso.onmicrosoft.com' }
            Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-AcceptedDomain' } { @([pscustomobject]@{ DomainName = 'contoso.onmicrosoft.com' }) }
        }

        It 'refuses a null-MX domain before anything is sent to Exchange' {
            Mock Resolve-DnsHttpsQuery { [pscustomobject]@{ Status = 0; Answer = @([pscustomobject]@{ type = 15; data = '0 .' }) } }
            $script:Body | Add-Member -NotePropertyName Recipients -NotePropertyValue 'someone@example.com'
            $Response = Invoke-ExecTestMessage -Request (New-Request $script:Body)
            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Match 'example\.com'
            Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Test-Message' }
        }

        It 'refuses a domain that does not exist' {
            Mock Resolve-DnsHttpsQuery { [pscustomobject]@{ Status = 3; Answer = $null } }
            $script:Body | Add-Member -NotePropertyName Recipients -NotePropertyValue 'someone@nowhere.example'
            (Invoke-ExecTestMessage -Request (New-Request $script:Body)).StatusCode | Should -Be 400
            Should -Invoke New-ExoRequest -Times 0 -ParameterFilter { $cmdlet -eq 'Test-Message' }
        }

        It 'never looks up the tenant''s own domains, and a failed lookup does not block' {
            Mock Resolve-DnsHttpsQuery { throw 'resolver unavailable' }
            $script:Body | Add-Member -NotePropertyName Recipients -NotePropertyValue 'b@contoso.onmicrosoft.com, c@partner.example'
            (Invoke-ExecTestMessage -Request (New-Request $script:Body)).StatusCode | Should -Be 200
            Should -Invoke Resolve-DnsHttpsQuery -Times 1 -Exactly -ParameterFilter { $Domain -eq 'partner.example' }
            Should -Invoke Resolve-DnsHttpsQuery -Times 0 -ParameterFilter { $Domain -eq 'contoso.onmicrosoft.com' }
            Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdlet -eq 'Test-Message' }
        }
    }
}
