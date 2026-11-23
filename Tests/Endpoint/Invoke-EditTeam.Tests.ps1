BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    $FunctionPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-EditTeam.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $Modules 'CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . $FunctionPath

    $script:TeamId = '11111111-2222-3333-4444-555555555555'
    function Invoke-Edit {
        param([hashtable]$Body)
        $Full = @{ tenantFilter = 'contoso.com'; TeamID = $script:TeamId }
        foreach ($Key in $Body.Keys) { $Full[$Key] = $Body[$Key] }
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'EditTeam' }; Headers = @{}; Body = [pscustomobject]$Full }
        Invoke-EditTeam -Request $Request -TriggerMetadata $null
    }
}

Describe 'Invoke-EditTeam' {
    BeforeEach {
        $script:Call = $null
        Mock New-GraphPOSTRequest { $script:Call = @{ Uri = $uri; Type = $type; Body = $body | ConvertFrom-Json; AsApp = $AsApp } }
    }

    It 'patches only the allowed settings, as booleans, with application auth' {
        $Response = Invoke-Edit @{
            memberSettings    = @{ allowCreateUpdateChannels = $false; allowDeleteChannels = 'true'; notASetting = $true }
            messagingSettings = @{ allowUserEditMessages = $true }
            displayName       = 'Renamed'
        }

        $Response.StatusCode | Should -Be 200
        $script:Call.Uri | Should -Be "https://graph.microsoft.com/beta/teams/$($script:TeamId)"
        $script:Call.Type | Should -Be 'PATCH'
        $script:Call.AsApp | Should -BeTrue
        $script:Call.Body.memberSettings.allowCreateUpdateChannels | Should -BeExactly $false
        $script:Call.Body.memberSettings.allowDeleteChannels | Should -BeExactly $true
        $script:Call.Body.memberSettings.allowDeleteChannels | Should -BeOfType [bool]
        $script:Call.Body.memberSettings.PSObject.Properties.Name | Should -Not -Contain 'notASetting'
        $script:Call.Body.messagingSettings.allowUserEditMessages | Should -BeExactly $true
        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'displayName'
        $script:Call.Body.PSObject.Properties.Name | Should -Not -Contain 'guestSettings'
    }

    It 'passes the Giphy rating from a picker' {
        $null = Invoke-Edit @{ funSettings = @{ allowGiphy = $true; giphyContentRating = @{ label = 'Strict'; value = 'strict' } } }

        $script:Call.Body.funSettings.giphyContentRating | Should -Be 'strict'
        $script:Call.Body.funSettings.allowGiphy | Should -BeExactly $true
    }

    It 'rejects <Case> without calling Graph' -ForEach @(
        @{ Case = 'an unknown Giphy rating'; Body = @{ funSettings = @{ giphyContentRating = 'anything' } } }
        @{ Case = 'nothing to change'; Body = @{ displayName = 'x' } }
        @{ Case = 'a team id that is not a GUID'; Body = @{ TeamID = 'abc/def'; funSettings = @{ allowGiphy = $true } } }
    ) {
        $Response = Invoke-Edit $Body

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'returns the Graph error with a failure status' {
        Mock New-GraphPOSTRequest { throw 'Team is archived' }

        $Response = Invoke-Edit @{ funSettings = @{ allowGiphy = $false } }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*Team is archived*'
    }
}
