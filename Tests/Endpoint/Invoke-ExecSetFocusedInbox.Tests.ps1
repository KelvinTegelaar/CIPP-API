BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetFocusedInbox.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }

    . $FunctionPath

    function Invoke-Set {
        param([hashtable]$Body)
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSetFocusedInbox' }; Headers = @{}; Body = [pscustomobject]$Body }
        Invoke-ExecSetFocusedInbox -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-ExecSetFocusedInbox' {
    BeforeEach { Mock New-ExoRequest {} }

    It 'sets Focused Inbox <State> for the mailbox' -ForEach @(
        @{ Value = $true; Expected = $true; State = 'on' }
        @{ Value = $false; Expected = $false; State = 'off' }
        @{ Value = 'false'; Expected = $false; State = 'off' }
    ) {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; FocusedInboxOn = $Value }

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be "Turned Focused Inbox $State for a@contoso.com"
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and $cmdlet -eq 'Set-FocusedInbox' -and
            $cmdParams.Identity -eq 'a@contoso.com' -and $cmdParams.FocusedInboxOn -is [bool] -and $cmdParams.FocusedInboxOn -eq $Expected
        }
    }

    It 'rejects a request with no mailbox' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; FocusedInboxOn = $true }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'rejects a missing or invalid state instead of turning it off' -ForEach @(
        @{ Value = $null }
        @{ Value = 'yes' }
    ) {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; FocusedInboxOn = $Value }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'returns the Exchange error with a failure status' {
        Mock New-ExoRequest { throw 'mailbox not found' }

        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; FocusedInboxOn = $true }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*mailbox not found*'
    }
}
