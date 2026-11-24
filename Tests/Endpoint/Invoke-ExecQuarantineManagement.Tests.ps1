# Pester tests for Invoke-ExecQuarantineManagement
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecQuarantineManagement.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecQuarantineManagement.ps1 under Modules/' }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CippBulkStatusCode {
        param([int]$Total, [int]$Failed)
        if ($Failed -le 0) { return [System.Net.HttpStatusCode]::OK }
        if ($Failed -ge $Total) { return [System.Net.HttpStatusCode]::InternalServerError }
        [System.Net.HttpStatusCode]::MultiStatus
    }

    . $FunctionPath
}

Describe 'Invoke-ExecQuarantineManagement release and allow sender' {
    BeforeAll {
        $script:Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecQuarantineManagement' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter  = 'contoso.onmicrosoft.com'
                Identity      = 'q-1'
                Type          = 'Release'
                AllowSender   = $true
                SenderAddress = 'new@sender.test'
                PolicyName    = 'Default'
            }
        }
    }
    BeforeEach { Mock Write-LogMessage {} }

    It 'reports a partial result when the allow-list step fails' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-HostedContentFilterPolicy') { throw 'Policy Default not found' }
        }
        $Response = Invoke-ExecQuarantineManagement -Request $script:Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::MultiStatus)
        ($Response.Body.Results | Where-Object state -EQ 'error').resultText | Should -Match 'Policy Default not found'
        ($Response.Body.Results | Where-Object state -EQ 'success').resultText | Should -Match 'Successfully processed'
    }

    It 'keeps existing allowed senders stored as plain strings' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-HostedContentFilterPolicy') { [pscustomobject]@{ AllowedSenders = @('a@x.test', 'b@x.test') } }
        }
        $Response = Invoke-ExecQuarantineManagement -Request $script:Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-HostedContentFilterPolicy' -and
            (@($cmdParams.AllowedSenders) -join ',') -eq 'a@x.test,b@x.test,new@sender.test'
        }
    }

    It 'keeps existing allowed senders stored as Sender.Address objects' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-HostedContentFilterPolicy') {
                [pscustomobject]@{ AllowedSenders = @([pscustomobject]@{ Sender = [pscustomobject]@{ Address = 'a@x.test' } }) }
            }
        }
        $null = Invoke-ExecQuarantineManagement -Request $script:Request -TriggerMetadata $null
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-HostedContentFilterPolicy' -and
            (@($cmdParams.AllowedSenders) -join ',') -eq 'a@x.test,new@sender.test'
        }
    }
}
