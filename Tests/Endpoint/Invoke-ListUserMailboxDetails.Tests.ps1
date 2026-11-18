# Pester tests for the forwarding fields of Invoke-ListUserMailboxDetails.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $noPagination, $AsApp) }
    function New-ExoBulkRequest { param($TenantId, $CmdletArray, $returnWithCommand, $Anchor) }
    function Get-CIPPAutoExpandingArchiveState { param($MailboxAutoExpandingArchiveEnabled, $OrgAutoExpandingArchiveEnabled) }
    function Get-ExoOnlineStringBytes { param($SizeString) 0 }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ListUserMailboxDetails.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-DetailsRequest {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListUserMailboxDetails' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.com'; UserID = 'user-guid'; userMail = 'sseck@contoso.com' }
        }
    }

    function Set-Mailbox {
        param($ForwardingAddress, $ForwardingSmtpAddress)
        $script:Mailbox = [pscustomobject]@{
            ArchiveGuid           = '00000000-0000-0000-0000-000000000000'
            ForwardingAddress     = $ForwardingAddress
            ForwardingSmtpAddress = $ForwardingSmtpAddress
            EmailAddresses        = @('SMTP:sseck@contoso.com')
        }
    }
}

Describe 'Invoke-ListUserMailboxDetails - forwarding' {
    BeforeEach {
        Set-Mailbox
        $script:Contacts = @()
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Get-CIPPAutoExpandingArchiveState -MockWith { @{ AutoExpandingArchive = $false; AutoExpandingArchiveScope = $null } }
        Mock -CommandName New-ExoBulkRequest -MockWith { [pscustomobject]@{ 'Get-Mailbox' = $script:Mailbox } }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ id = 'forward-user-guid'; userPrincipalName = 'boss@contoso.com'; displayName = 'Boss'; mailNickname = 'boss' })
        } -ParameterFilter { $uri -like '*/beta/users*' }
        Mock -CommandName New-GraphGetRequest -MockWith { $script:Contacts } -ParameterFilter { $uri -like '*/beta/contacts*' }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ ItemCount = 0; TotalItemSize = '0 GB' } } -ParameterFilter { $uri -like '*GetMailboxStatistics*' }
    }

    It 'returns the contact with its object ID when the forward resolves to a contact' {
        Set-Mailbox -ForwardingAddress 'Ann Contact'
        $script:Contacts = @([pscustomobject]@{ id = 'contact-guid'; displayName = 'Ann Contact'; mail = 'ann@gmail.com'; mailNickname = 'AnnContact' })

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'ann@gmail.com'
        $Body.ForwardingContact.id | Should -Be 'contact-guid'
        $Body.ForwardingContact.displayName | Should -Be 'Ann Contact'
        $Body.ForwardingContact.mail | Should -Be 'ann@gmail.com'
        @($Body.ForwardingContact.PSObject.Properties.Name) | Should -Be @('id', 'displayName', 'mail')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/beta/contacts*' -and $uri -like '*$select=id,*' }
    }

    It 'returns the UPN and no contact when the forward resolves to a user' {
        Set-Mailbox -ForwardingAddress 'boss'

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'boss@contoso.com'
        $Body.ForwardingContact | Should -BeNullOrEmpty
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/beta/contacts*' }
    }

    It 'passes an internal forward that is already an address through, with no contact' {
        Set-Mailbox -ForwardingAddress 'shared@contoso.com'

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'shared@contoso.com'
        $Body.ForwardingContact | Should -BeNullOrEmpty
    }

    It 'keeps the raw value and no contact when nothing matches' {
        Set-Mailbox -ForwardingAddress 'Unknown Recipient'

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'Unknown Recipient'
        $Body.ForwardingContact | Should -BeNullOrEmpty
    }

    It 'keeps the raw value and no contact when the contact lookup fails' {
        Set-Mailbox -ForwardingAddress 'Ann Contact'
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph down' } -ParameterFilter { $uri -like '*/beta/contacts*' }

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'Ann Contact'
        $Body.ForwardingContact | Should -BeNullOrEmpty
    }

    It 'returns the external address unchanged and no contact for external forwarding' {
        Set-Mailbox -ForwardingSmtpAddress 'smtp:someone@external.com'

        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -Be 'someone@external.com'
        $Body.ForwardingContact | Should -BeNullOrEmpty
    }

    It 'returns nothing for either field when forwarding is off' {
        $Body = (Invoke-ListUserMailboxDetails -Request (New-DetailsRequest)).Body[0]

        $Body.ForwardingAddress | Should -BeNullOrEmpty
        $Body.ForwardingContact | Should -BeNullOrEmpty
        $Body.Contains('ForwardingContact') | Should -BeTrue
    }
}
