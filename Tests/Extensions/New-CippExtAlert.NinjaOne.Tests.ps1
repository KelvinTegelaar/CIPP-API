# Pester tests for routing an alert to NinjaOne Ticketing from New-CippExtAlert: the organisation
# comes from the existing NinjaOne tenant mapping, and an unmapped tenant is skipped with a warning.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-Tenants { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    function New-NinjaOneTicket { param($Title, $Description, $Client, $TicketPriority, $ConsolidationKey, $UserUPN, $DisplayName, $TenantCustomerId, $AffectedDevice) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-HaloPSATicket { param($Title, $Description, $Client) }
    function New-GradientAlert { param($Title, $Description, $Client) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/New-CippExtAlert.ps1')

    function New-ConfigRow {
        param([bool]$TicketingEnabled = $true, [bool]$LinkTicketsToUsers = $false)
        [pscustomobject]@{
            config = (@{
                    NinjaOne = @{ Enabled = $true; TicketingEnabled = $TicketingEnabled; LinkTicketsToUsers = $LinkTicketsToUsers; Instance = 'eu.ninjarmm.com' }
                } | ConvertTo-Json -Depth 5)
        }
    }
}

Describe 'New-CippExtAlert - NinjaOne ticketing' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.test' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-NinjaOneTicket -MockWith { 'Ticket created in NinjaOne: 1' }
        $script:Mapped = $true
        $script:TicketingEnabled = $true
        $script:LinkUsers = $false
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ userPrincipalName = 'resolved@contoso.test'; displayName = 'Resolved User' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -TicketingEnabled $script:TicketingEnabled -LinkTicketsToUsers $script:LinkUsers }
            if ($script:Mapped -and $Filter -like "*NinjaOneMapping*RowKey eq 'tenant-guid'*") {
                return [pscustomobject]@{ PartitionKey = 'NinjaOneMapping'; RowKey = 'tenant-guid'; IntegrationId = '77'; IntegrationName = 'Contoso' }
            }
            $null
        }
        $script:Alert = [pscustomobject]@{
            TenantId            = 'contoso.test'
            AlertTitle          = '[CIPP] Something happened'
            AlertText           = '<p>details</p>'
            PsaTicketPriority   = 'HIGH'
            PSAConsolidationKey = 'stable-key'
            PsaTicketId         = 1234
        }
    }

    It 'raises the ticket against the mapped organisation and passes priority and consolidation key' {
        $Result = New-CippExtAlert -Alert $script:Alert
        $Result | Should -Be 'Ticket created in NinjaOne: 1'
        Should -Invoke -CommandName New-NinjaOneTicket -Times 1 -ParameterFilter {
            $Client -eq '77' -and $Title -eq '[CIPP] Something happened' -and $Description -eq '<p>details</p>' -and
            $TicketPriority -eq 'HIGH' -and $ConsolidationKey -eq 'stable-key'
        }
    }

    It 'does not forward the HaloPSA ticket id to NinjaOne' {
        $null = New-CippExtAlert -Alert $script:Alert
        Should -Invoke -CommandName New-NinjaOneTicket -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('TicketId') }
    }

    It 'passes the affected user through when linking is on, resolving the UPN from Graph if needed' {
        $script:LinkUsers = $true
        $script:Alert | Add-Member -NotePropertyName AffectedUser -NotePropertyValue ([pscustomobject]@{ AzureOID = '11111111-1111-1111-1111-111111111111' }) -Force
        $null = New-CippExtAlert -Alert $script:Alert
        Should -Invoke -CommandName New-NinjaOneTicket -Times 1 -ParameterFilter { $UserUPN -eq 'resolved@contoso.test' -and $DisplayName -eq 'Resolved User' }
    }

    It 'does not pass the affected user when linking is off' {
        $script:Alert | Add-Member -NotePropertyName AffectedUser -NotePropertyValue ([pscustomobject]@{ UPN = 'jane@contoso.test' }) -Force
        $null = New-CippExtAlert -Alert $script:Alert
        Should -Invoke -CommandName New-NinjaOneTicket -Times 1 -ParameterFilter { -not $PSBoundParameters.ContainsKey('UserUPN') }
        Should -Invoke -CommandName New-GraphGetRequest -Times 0
    }

    It 'passes the affected device with the tenant customer id' {
        $script:Alert | Add-Member -NotePropertyName AffectedDevice -NotePropertyValue ([pscustomobject]@{ IntuneId = 'intune-1'; SerialNumber = 'S1' }) -Force
        $null = New-CippExtAlert -Alert $script:Alert
        Should -Invoke -CommandName New-NinjaOneTicket -Times 1 -ParameterFilter { $AffectedDevice.IntuneId -eq 'intune-1' -and $TenantCustomerId -eq 'tenant-guid' }
    }

    It 'skips an unmapped tenant with a warning and without throwing' {
        $script:Mapped = $false
        $Result = New-CippExtAlert -Alert $script:Alert
        $Result | Should -Match '^Skipped NinjaOne ticket: tenant contoso.test is not mapped'
        Should -Invoke -CommandName New-NinjaOneTicket -Times 0
        Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Warning' -and $message -like 'No NinjaOne organisation mapping*' }
    }

    It 'does nothing when ticketing is switched off for the integration' {
        $script:TicketingEnabled = $false
        $Result = New-CippExtAlert -Alert $script:Alert
        $Result | Should -BeNullOrEmpty
        Should -Invoke -CommandName New-NinjaOneTicket -Times 0
    }
}
