# Pester tests for Invoke-ExecExtensionOAuth: the authorize URL, state checks on exchange, and
# where the refresh token ends up.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-ExtensionAPIKey { param([string]$Extension) }
    function Set-ExtensionAPIKey { param([string]$Extension, [string]$APIKey) }
    function Remove-ExtensionAPIKey { param([string]$Extension) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData, $headers) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }

    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionOAuth.ps1')

    function New-Request {
        param($Body = @{}, $Query = @{})
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecExtensionOAuth' }
            Headers = @{ 'x-ms-original-url' = 'https://cipp.example.com/cipp/integrations/configure' }
            Body    = [pscustomobject]$Body
            Query   = [pscustomobject]$Query
        }
    }
}

Describe 'Invoke-ExecExtensionOAuth' {
    BeforeEach {
        $script:Added = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:StateRow = $null
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($TableName -eq 'Extensionsconfig') {
                return [pscustomobject]@{ config = (@{ NinjaOne = @{ Instance = 'eu.ninjarmm.com'; ClientID = 'client-id' } } | ConvertTo-Json -Depth 5) }
            }
            if ($Filter -like "PartitionKey eq 'State'*") { return $script:StateRow }
            $null
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { param($TableName, $Entity, [switch]$Force) $script:Added.Add($Entity) }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($TableName, $Entity, [switch]$Force) $script:Removed.Add($Entity) }
        Mock -CommandName Get-ExtensionAPIKey -MockWith { 'client-secret' }
        Mock -CommandName Set-ExtensionAPIKey -MockWith { $true }
        Mock -CommandName Remove-ExtensionAPIKey -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-NormalizedError -MockWith { param($Message) $Message }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Body, $ContentType)
            $script:TokenRequest = [pscustomobject]@{ Uri = $Uri; Body = $Body }
            @{ access_token = 'access'; refresh_token = 'refresh-1'; scope = 'monitoring management offline_access' }
        }
    }

    It 'start stores a state row and returns the NinjaOne authorize URL with the CIPP redirect' {
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'NinjaOne'; Action = 'start' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:Added.Count | Should -Be 1
        $State = $script:Added[0].RowKey
        $State | Should -Match '^[0-9a-f]{32}$'
        $script:Added[0].Extension | Should -Be 'NinjaOne'
        $Response.Body.redirectUri | Should -Be 'https://cipp.example.com/authredirect'
        $Response.Body.authorizeUrl | Should -Be "https://eu.ninjarmm.com/ws/oauth/authorize?response_type=code&client_id=client-id&redirect_uri=https%3A%2F%2Fcipp.example.com%2Fauthredirect&scope=monitoring%20management%20offline_access&state=$State"
    }

    It 'exchange redeems a fresh state, stores the refresh token and records the connection' {
        $script:StateRow = [pscustomobject]@{ PartitionKey = 'State'; RowKey = 'abc'; Extension = 'NinjaOne'; Created = [datetime]::UtcNow.AddMinutes(-1).ToString('o') }
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'NinjaOne'; Action = 'exchange'; code = 'the-code'; state = 'abc' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $script:TokenRequest.Uri | Should -Be 'https://eu.ninjarmm.com/ws/oauth/token'
        $script:TokenRequest.Body.grant_type | Should -Be 'authorization_code'
        $script:TokenRequest.Body.code | Should -Be 'the-code'
        $script:TokenRequest.Body.redirect_uri | Should -Be 'https://cipp.example.com/authredirect'
        $script:TokenRequest.Body.client_secret | Should -Be 'client-secret'
        Should -Invoke -CommandName Set-ExtensionAPIKey -Times 1 -ParameterFilter { $Extension -eq 'NinjaOneRefreshToken' -and $APIKey -eq 'refresh-1' }
        $script:Removed[0].RowKey | Should -Be 'abc'
        ($script:Added | Where-Object { $_.PartitionKey -eq 'Connection' }).RowKey | Should -Be 'NinjaOne'
    }

    It 'exchange rejects an unknown state without calling the token endpoint' {
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'NinjaOne'; Action = 'exchange'; code = 'c'; state = 'nope' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'unknown or expired'
        Should -Invoke -CommandName Invoke-RestMethod -Times 0
        Should -Invoke -CommandName Set-ExtensionAPIKey -Times 0
    }

    It 'exchange rejects an expired state and burns it' {
        $script:StateRow = [pscustomobject]@{ PartitionKey = 'State'; RowKey = 'old'; Extension = 'NinjaOne'; Created = [datetime]::UtcNow.AddMinutes(-11).ToString('o') }
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'NinjaOne'; Action = 'exchange'; code = 'c'; state = 'old' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $script:Removed[0].RowKey | Should -Be 'old'
        Should -Invoke -CommandName Invoke-RestMethod -Times 0
    }

    It 'keeps the port of a non-standard origin in the redirect' {
        $Request = New-Request -Body @{ Extension = 'NinjaOne'; Action = 'status' }
        $Request.Headers = @{ 'x-ms-original-url' = 'http://localhost:5196/api/ExecExtensionOAuth' }
        (Invoke-ExecExtensionOAuth -Request $Request).Body.redirectUri | Should -Be 'http://localhost:5196/authredirect'
    }

    It 'refuses an extension that is not in the provider list' {
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'HaloPSA'; Action = 'start' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        $script:Added.Count | Should -Be 0
    }

    It 'disconnect removes the secret and the connection row' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($TableName -eq 'Extensionsconfig') { return [pscustomobject]@{ config = (@{ NinjaOne = @{ Instance = 'eu.ninjarmm.com'; ClientID = 'client-id' } } | ConvertTo-Json -Depth 5) } }
            if ($Filter -like "PartitionKey eq 'Connection'*") { return [pscustomobject]@{ PartitionKey = 'Connection'; RowKey = 'NinjaOne' } }
            $null
        }
        $Response = Invoke-ExecExtensionOAuth -Request (New-Request -Body @{ Extension = 'NinjaOne'; Action = 'disconnect' })
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        Should -Invoke -CommandName Remove-ExtensionAPIKey -Times 1 -ParameterFilter { $Extension -eq 'NinjaOneRefreshToken' }
        $script:Removed[0].RowKey | Should -Be 'NinjaOne'
    }
}
