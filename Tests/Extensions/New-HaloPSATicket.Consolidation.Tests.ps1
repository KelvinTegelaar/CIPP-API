# Pester tests for HaloPSA ticket consolidation keys.
# Scheduled CIPP alerts may include dynamic data such as timestamps in their visible title.
# A stable ConsolidationKey allows those alerts to reuse the same HaloPSA ticket while
# preserving the original displayed title.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/Halo/New-HaloPSATicket.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-HaloToken { param($configuration) }
    function Get-CippUserAgent { 'CIPP/test' }
    function Get-HaloUser { param($AzureOID, $Email, $ClientId, $Configuration, $Token) }
    function Get-StringHash { param($String) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath

    function New-HaloConfigRow {
        param(
            [bool]$ConsolidateTickets = $true,
            [bool]$LinkTicketsToUsers = $false
        )

        [pscustomobject]@{
            config = (@{
                    HaloPSA = @{
                        Enabled            = $true
                        ResourceURL        = 'https://halo.example.com/api'
                        TicketType         = 21
                        ConsolidateTickets = $ConsolidateTickets
                        LinkTicketsToUsers = $LinkTicketsToUsers
                        Outcome            = @{ label = 'CIPP Update'; value = 155 }
                    }
                } | ConvertTo-Json -Depth 5)
        }
    }
}

Describe 'New-HaloPSATicket - consolidation key' {
    BeforeEach {
        $script:HashInput = $null
        $script:TicketLookupFilter = $null

        Mock -CommandName Get-CIPPTable -MockWith {
            param([string]$TableName)
            @{ TableName = $TableName }
        }

        Mock -CommandName Get-HaloToken -MockWith {
            @{ access_token = 'token' }
        }

        Mock -CommandName Get-StringHash -MockWith {
            param($String)
            $script:HashInput = $String
            'stablehash'
        }

        Mock -CommandName Get-HaloUser -MockWith {
            $null
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)

            if ($Filter) {
                $script:TicketLookupFilter = $Filter
                return [pscustomobject]@{
                    TicketID = 999
                }
            }

            New-HaloConfigRow
        }

        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)

            if ($Method -eq 'Get') {
                return @{
                    id            = 999
                    hasbeenclosed = $false
                }
            }

            if ($Uri -like '*/actions') {
                return @{
                    id = 5555
                }
            }

            return @{
                id = 1000
            }
        }
    }

    It 'preserves title-based consolidation when no key is supplied' {
        $null = New-HaloPSATicket `
            -title '[CIPP] contoso.com CIPP Alert: Alerts found starting at 09/22/2026 09:45:00' `
            -description '<p>body</p>' `
            -client 19

        $script:HashInput |
            Should -Be '[CIPP] contoso.com CIPP Alert: Alerts found starting at 09/22/2026 09:45:00'
    }

    It 'uses the stable consolidation key instead of the dynamic title' {
        $null = New-HaloPSATicket `
            -title '[CIPP] contoso.com CIPP Alert: Alerts found starting at 09/22/2026 09:45:00' `
            -description '<p>body</p>' `
            -client 19 `
            -ConsolidationKey 'contoso.com|Alerts'

        $script:HashInput | Should -Be 'contoso.com|Alerts'
    }

    It 'produces the same consolidation input for different timestamped titles' {
        $null = New-HaloPSATicket `
            -title '[CIPP] contoso.com CIPP Alert: Alerts found starting at 09/22/2026 09:45:00' `
            -description '<p>first</p>' `
            -client 19 `
            -ConsolidationKey 'contoso.com|Alerts'

        $FirstHashInput = $script:HashInput

        $null = New-HaloPSATicket `
            -title '[CIPP] contoso.com CIPP Alert: Alerts found starting at 09/22/2026 10:00:00' `
            -description '<p>second</p>' `
            -client 19 `
            -ConsolidationKey 'contoso.com|Alerts'

        $SecondHashInput = $script:HashInput

        $FirstHashInput | Should -Be 'contoso.com|Alerts'
        $SecondHashInput | Should -Be $FirstHashInput
    }

    It 'uses the stable hash in the PSATickets row key lookup' {
        $null = New-HaloPSATicket `
            -title '[CIPP] dynamic title' `
            -description '<p>body</p>' `
            -client 19 `
            -ConsolidationKey 'contoso.com|Alerts'

        $script:TicketLookupFilter |
            Should -Be "PartitionKey eq 'HaloPSA' and RowKey eq '19-stablehash'"
    }
}

Describe 'New-HaloPSATicket - consolidation key with affected users' {
    BeforeEach {
        $script:HashInput = $null

        Mock -CommandName Get-CIPPTable -MockWith {
            param([string]$TableName)
            @{ TableName = $TableName }
        }

        Mock -CommandName Get-HaloToken -MockWith {
            @{ access_token = 'token' }
        }

        Mock -CommandName Get-StringHash -MockWith {
            param($String)
            $script:HashInput = $String
            'stablehash'
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }

        Mock -CommandName Get-HaloUser -MockWith {
            [pscustomobject]@{
                id      = 123
                site_id = 7
            }
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)

            if ($Filter) {
                return [pscustomobject]@{
                    TicketID = 999
                }
            }

            New-HaloConfigRow -LinkTicketsToUsers $true
        }

        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)

            if ($Method -eq 'Get') {
                return @{
                    id            = 999
                    hasbeenclosed = $false
                }
            }

            return @{
                id = 5555
            }
        }
    }

    It 'keeps affected users separated when a stable consolidation key is supplied' {
        $null = New-HaloPSATicket `
            -title '[CIPP] dynamic title' `
            -description '<p>body</p>' `
            -client 19 `
            -UserUPN 'user1@contoso.com' `
            -AzureOID '11111111-1111-1111-1111-111111111111' `
            -ConsolidationKey 'contoso.com|Alerts'

        $script:HashInput |
            Should -Be 'contoso.com|Alerts|user1@contoso.com'
    }
}
