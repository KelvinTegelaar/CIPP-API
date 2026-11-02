# Pester tests for Get-NinjaOneTicketUser: exact email match inside one organisation, end user preferred.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    function Get-NormalizedError { param($Message) }
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/NinjaOne/Get-NinjaOneTicketUser.ps1')
    $script:Config = [pscustomobject]@{ Instance = 'eu.ninjarmm.com' }
    $script:Token = @{ access_token = 'token' }
}

Describe 'Get-NinjaOneTicketUser' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-NormalizedError -MockWith { param($Message) $Message }
        $script:Uris = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Headers, $ContentType)
            $script:Uris.Add($Uri)
            @(
                @{ uid = 'contact-uid'; id = 1; clientId = 14; email = 'Jane@Contoso.com'; userType = 'CONTACT'; firstName = 'Jane'; lastName = 'C' }
                @{ uid = 'other-org';   id = 2; clientId = 15; email = 'jane@contoso.com'; userType = 'END_USER'; firstName = 'Jane'; lastName = 'O' }
                @{ uid = 'enduser-uid'; id = 3; clientId = 14; email = 'jane@contoso.com'; userType = 'END_USER'; firstName = 'Jane'; lastName = 'Doe' }
                @{ uid = 'partial';     id = 4; clientId = 14; email = 'jane@contoso.com.au'; userType = 'END_USER' }
            )
        }
    }

    It 'queries the organisation by email and prefers the end user over a contact' {
        $User = Get-NinjaOneTicketUser -Emails 'JANE@contoso.com' -ClientId '14' -Configuration $script:Config -Token $script:Token
        $User.uid | Should -Be 'enduser-uid'
        $User.displayName | Should -Be 'Jane Doe'
        $script:Uris[0] | Should -Be 'https://eu.ninjarmm.com/api/v2/ticketing/app-user-contact?clientId=14&searchCriteria=JANE%40contoso.com&pageSize=50'
    }

    It 'tries the next email when the first has no exact match' {
        $User = Get-NinjaOneTicketUser -Emails @('nobody@contoso.com', 'jane@contoso.com') -ClientId 14 -Configuration $script:Config -Token $script:Token
        $User.uid | Should -Be 'enduser-uid'
        $script:Uris.Count | Should -Be 2
    }

    It 'returns nothing for a partial or other-organisation match' {
        Get-NinjaOneTicketUser -Emails 'jane@contoso.co' -ClientId 14 -Configuration $script:Config -Token $script:Token | Should -BeNullOrEmpty
    }

    It 'returns nothing and warns when the search fails' {
        Mock -CommandName Invoke-RestMethod -MockWith { throw 'HTTP 403' }
        Get-NinjaOneTicketUser -Emails 'jane@contoso.com' -ClientId 14 -Configuration $script:Config -Token $script:Token | Should -BeNullOrEmpty
        Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Warning' }
    }
}
