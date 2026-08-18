# Pester tests for the HaloPSA ticket payload built by New-HaloPSATicket.
# Halo records tickets created over the API as 'Manual' unless the payload carries a source, so the
# integration gained an optional HaloPSA.RequestSource setting (#321). The guard around it is easy
# to get wrong: Halo source ids include 0 (Email) and negatives (built-in integration sources), and
# in PowerShell both $null -as [int] and '' -as [int] evaluate to 0 - so a naive cast would stamp
# Email on every install that left the setting blank.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/Halo/New-HaloPSATicket.ps1'

    # Stubs for the dependencies we mock.
    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-HaloToken { param($configuration) }
    function Get-HaloUser { param($AzureOID, $Email, $ClientId, $Configuration, $Token) }
    function Get-StringHash { param($String) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath

    # Builds the single Extensionsconfig row the function reads. Pass -NoRequestSource to leave the
    # property off entirely, which is what an existing install looks like.
    function New-HaloConfigRow {
        param(
            $RequestSource,
            [switch]$NoRequestSource,
            [bool]$ConsolidateTickets = $false
        )
        $Halo = @{
            Enabled            = $true
            ResourceURL        = 'https://halo.example.com/api'
            TicketType         = 21
            ConsolidateTickets = $ConsolidateTickets
        }
        if (-not $NoRequestSource) { $Halo.RequestSource = $RequestSource }
        [pscustomobject]@{ config = (@{ HaloPSA = $Halo } | ConvertTo-Json -Depth 5) }
    }

    # Runs the function against a given config and hands back the deserialised POST body.
    function Get-TicketPayload {
        param($ConfigRow)
        $script:CapturedUri = $null
        $script:CapturedBody = $null
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $ConfigRow }
        New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 | Out-Null
        if ($null -eq $script:CapturedBody) { return $null }
        # The function posts a single-element array.
        @($script:CapturedBody | ConvertFrom-Json)[0]
    }
}

Describe 'New-HaloPSATicket - request source' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-HaloToken -MockWith { @{ access_token = 'token' } }
        Mock -CommandName Get-StringHash -MockWith { 'hash' }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)
            $script:CapturedUri = $Uri
            $script:CapturedBody = $Body
            @{ id = 123 }
        }
    }

    It 'omits source entirely when the setting has never been configured' {
        # The backwards-compatibility guarantee: existing installs must post exactly what they
        # posted before, so Halo keeps applying its own default.
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -NoRequestSource)
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'source'
    }

    It 'sends source 0 rather than treating it as unset' {
        # Email is source id 0. Any falsy/-as [int] guard would drop or invent this.
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -RequestSource @{ label = 'Email'; value = 0 })
        $Payload.PSObject.Properties.Name | Should -Contain 'source'
        $Payload.source | Should -Be 0
    }

    It 'sends negative source ids' {
        # Halo's built-in integration sources are negative, e.g. -9 Ninja RMM.
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -RequestSource @{ label = 'Ninja RMM'; value = -9 })
        $Payload.source | Should -Be -9
    }

    It 'accepts a raw scalar as well as the autocomplete object' {
        # Config can hold either shape, hence the .value ?? $x idiom.
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -RequestSource 42)
        $Payload.source | Should -Be 42
    }

    It 'omits source when the setting was cleared to an empty string' {
        # '' -as [int] is 0, so without an explicit blank check this would become Email.
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -RequestSource '')
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'source'
    }

    It 'omits source and warns when the stored value is not an integer' {
        $Payload = Get-TicketPayload -ConfigRow (New-HaloConfigRow -RequestSource 'not-a-number')
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'source'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*RequestSource*' }
    }

    It 'does not put source on the note action when consolidating onto an existing ticket' {
        # The consolidation path posts to /actions, which has no source field.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($Filter) { return [pscustomobject]@{ TicketID = 999 } }
            New-HaloConfigRow -RequestSource @{ label = 'CIPP'; value = 42 } -ConsolidateTickets $true
        }
        $script:CapturedUri = $null
        $script:CapturedBody = $null
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)
            if ($Method -eq 'Get') { return @{ id = 999; hasbeenclosed = $false } }
            $script:CapturedUri = $Uri
            $script:CapturedBody = $Body
            @{ id = 999 }
        }

        New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 | Out-Null

        $script:CapturedUri | Should -BeLike '*/actions'
        $Action = @($script:CapturedBody | ConvertFrom-Json)[0]
        $Action.PSObject.Properties.Name | Should -Not -Contain 'source'
    }
}
