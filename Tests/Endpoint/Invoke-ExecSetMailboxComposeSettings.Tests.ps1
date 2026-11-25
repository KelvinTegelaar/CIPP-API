BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetMailboxComposeSettings.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }

    . $FunctionPath

    function Invoke-Set {
        param([hashtable]$Body)
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSetMailboxComposeSettings' }; Headers = @{}; Body = [pscustomobject]$Body }
        Invoke-ExecSetMailboxComposeSettings -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-ExecSetMailboxComposeSettings' {
    BeforeEach { Mock New-ExoRequest {} }

    It 'sends only the settings given, typed as Exchange expects, anchored on the mailbox' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; MailSendUndoInterval = '10'; AlwaysShowFrom = 'true'; LinkPreviewEnabled = 'false'; AlwaysShowBcc = ''; DefaultFormat = 'PlainText' }

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and $cmdlet -eq 'Set-MailboxMessageConfiguration' -and $Anchor -eq 'a@contoso.com' -and
            (@($cmdParams.Keys | Sort-Object) -join ',') -eq 'AlwaysShowFrom,DefaultFormat,Identity,LinkPreviewEnabled,MailSendUndoInterval' -and
            $cmdParams.MailSendUndoInterval -is [int] -and $cmdParams.MailSendUndoInterval -eq 10 -and
            $cmdParams.AlwaysShowFrom -is [bool] -and $cmdParams.AlwaysShowFrom -and
            $cmdParams.LinkPreviewEnabled -is [bool] -and -not $cmdParams.LinkPreviewEnabled -and
            $cmdParams.DefaultFormat -eq 'PlainText'
        }
    }

    It 'sets the default font name, size and colour' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; DefaultFontName = ' Aptos '; DefaultFontSize = '11'; DefaultFontColor = '#1F2937' }

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdParams.DefaultFontName -eq 'Aptos' -and $cmdParams.DefaultFontSize -is [int] -and $cmdParams.DefaultFontSize -eq 11 -and $cmdParams.DefaultFontColor -eq '#1F2937'
        }
    }

    It 'accepts 0 to turn undo send off and JSON booleans from the API' {
        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; MailSendUndoInterval = 0; AlwaysShowBcc = $false }

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdParams.MailSendUndoInterval -eq 0 -and $cmdParams.AlwaysShowBcc -eq $false }
    }

    It 'rejects <Case> without writing anything' -ForEach @(
        @{ Case = 'no mailbox'; Body = @{ AlwaysShowFrom = 'true' } }
        @{ Case = 'no setting to change'; Body = @{ ID = 'a@contoso.com'; AlwaysShowFrom = '' } }
        @{ Case = 'an undo delay above 10'; Body = @{ ID = 'a@contoso.com'; MailSendUndoInterval = '11' } }
        @{ Case = 'a negative undo delay'; Body = @{ ID = 'a@contoso.com'; MailSendUndoInterval = '-1' } }
        @{ Case = 'a non-boolean switch'; Body = @{ ID = 'a@contoso.com'; AlwaysShowFrom = 'yes' } }
        @{ Case = 'an unknown format'; Body = @{ ID = 'a@contoso.com'; DefaultFormat = 'Rtf' } }
        @{ Case = 'an unknown read receipt option'; Body = @{ ID = 'a@contoso.com'; ReadReceiptResponse = 'Sometimes' } }
        @{ Case = 'a font size above 72'; Body = @{ ID = 'a@contoso.com'; DefaultFontSize = '73' } }
        @{ Case = 'a font size of 0'; Body = @{ ID = 'a@contoso.com'; DefaultFontSize = '0' } }
        @{ Case = 'a shorthand colour'; Body = @{ ID = 'a@contoso.com'; DefaultFontColor = '#000' } }
        @{ Case = 'a colour name'; Body = @{ ID = 'a@contoso.com'; DefaultFontColor = 'black' } }
        @{ Case = 'one bad setting among good ones'; Body = @{ ID = 'a@contoso.com'; AlwaysShowFrom = 'true'; MailSendUndoInterval = '30' } }
    ) {
        $Response = Invoke-Set ($Body + @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'returns the Exchange failure as an error status, not OK' {
        Mock New-ExoRequest { throw 'mailbox not found' }

        $Response = Invoke-Set @{ tenantFilter = 'contoso.com'; ID = 'a@contoso.com'; AlwaysShowFrom = 'true' }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'mailbox not found'
    }
}
