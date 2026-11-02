# Pester tests for New-NinjaOneTicket: the create payload, priority resolution, and the
# consolidation path that comments on an open ticket instead of raising another.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-NinjaOneUserToken { param($Configuration) }
    function Get-StringHash { param($String) }
    function Get-NinjaOneTicketUser { param([string[]]$Emails, $ClientId, $Configuration, $Token) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/NinjaOne/New-NinjaOneTicket.ps1')

    function New-ConfigRow {
        param($Extra = @{})
        $Config = @{
            Enabled          = $true
            TicketingEnabled = $true
            Instance         = 'eu.ninjarmm.com'
            TicketForm       = @{ label = 'CIPP'; value = 42 }
        }
        foreach ($Key in $Extra.Keys) { $Config[$Key] = $Extra[$Key] }
        [pscustomobject]@{ config = (@{ NinjaOne = $Config } | ConvertTo-Json -Depth 5) }
    }

    function Set-RestMock {
        param([bool]$TicketExists = $true, [string]$StatusName = 'OPEN', [int]$ParentId = 2000)
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:MockTicketExists = $TicketExists
        $script:MockStatusName = $StatusName
        $script:MockParentId = $ParentId
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers)
            $script:Calls.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body })
            if ($Method -eq 'GET' -and $Uri -like '*/devices-detailed*') {
                return @(@{ id = 501; system = @{ serialNumber = 'SER 123'; biosSerialNumber = 'SER123' } }, @{ id = 502; system = @{ serialNumber = 'OTHER' } })
            }
            if ($Method -eq 'GET') {
                if (-not $script:MockTicketExists) { throw 'HTTP 404 Not Found' }
                return @{ id = 1380; status = @{ name = $script:MockStatusName; parentId = $script:MockParentId } }
            }
            if ($Uri -like '*/comment') { return @{ id = 7 } }
            @{ id = 1382 }
        }
    }

    function Get-CreateCall { $script:Calls | Where-Object { $_.Uri -like '*/ticketing/ticket' -and $_.Method -eq 'POST' } | Select-Object -First 1 }
    function Get-CommentCall { $script:Calls | Where-Object { $_.Uri -like '*/comment' } | Select-Object -First 1 }
}

Describe 'New-NinjaOneTicket' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-NinjaOneUserToken -MockWith { @{ access_token = 'token' } }
        Mock -CommandName Get-StringHash -MockWith { 'hash' }
        Mock -CommandName Get-NinjaOneTicketUser -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-NormalizedError -MockWith { param($Message) $Message }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Set-RestMock
    }

    Context 'creating a ticket' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -Extra @{ TicketPriority = @{ label = 'Low'; value = 'LOW' } } }
                $null
            }
        }

        It 'posts the organisation, form, subject, default status and both description bodies' {
            $Result = New-NinjaOneTicket -Title 'Alert title' -Description '<p>Hello <b>world</b></p>' -Client '17'
            $Result | Should -Be 'Ticket created in NinjaOne: 1382'
            $Call = Get-CreateCall
            $Call.Uri | Should -Be 'https://eu.ninjarmm.com/api/v2/ticketing/ticket'
            $Body = $Call.Body | ConvertFrom-Json
            $Body.clientId | Should -Be 17
            $Body.ticketFormId | Should -Be 42
            $Body.subject | Should -Be 'Alert title'
            $Body.status | Should -Be '1000'
            $Body.description.public | Should -BeFalse
            $Body.description.htmlBody | Should -Be '<p>Hello <b>world</b></p>'
            $Body.description.body | Should -Be 'Hello world'
            $Body.priority | Should -Be 'LOW'
        }

        It 'uses the configured status and a valid per-alert priority over the integration default' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -Extra @{ TicketPriority = 'LOW'; TicketStatus = @{ label = 'Triage'; value = '2017' } } }
                $null
            }
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3 -TicketPriority @{ label = 'High'; value = 'high' }
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.status | Should -Be '2017'
            $Body.priority | Should -Be 'HIGH'
        }

        It 'ignores a HaloPSA priority id passed as the per-alert priority' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3 -TicketPriority 4
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.priority | Should -Be 'LOW'
        }

        It 'omits priority when neither source is usable' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow }
                $null
            }
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.PSObject.Properties.Name | Should -Not -Contain 'priority'
        }

        It 'does not record the ticket unless consolidation is on' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0
        }

        It 'refuses without a ticket form and does not call the API' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -Extra @{ TicketForm = $null } }
                $null
            }
            $Result = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3
            $Result | Should -Match '^Failed to send ticket to NinjaOne: no Ticket Form'
            $script:Calls.Count | Should -Be 0
        }

        It 'refuses when nobody has connected and does not call the API' {
            Mock -CommandName Get-NinjaOneUserToken -MockWith { $null }
            $Result = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3
            $Result | Should -Match '^Failed to send ticket to NinjaOne: ticketing is not connected'
            $script:Calls.Count | Should -Be 0
        }

        It 'reports an API failure in its return value instead of throwing' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'HTTP 400 Bad Request' }
            $Result = New-NinjaOneTicket -Title 't' -Description 'd' -Client 3
            $Result | Should -Be 'Failed to send ticket to NinjaOne: HTTP 400 Bad Request'
        }
    }

    Context 'linking the affected user and device' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -Extra @{ LinkTicketsToUsers = $true; ConsolidateTickets = $true } }
                if ($TableName -eq 'NinjaOneDeviceMap' -and $Filter -like "*M365ID eq 'intune-1'*") { return [pscustomobject]@{ NinjaOneID = '777'; M365ID = 'intune-1' } }
                if ($TableName -eq 'NinjaOneDeviceMap' -and $Filter -like "*RowKey eq 'entra-dev-1'*") { return [pscustomobject]@{ NinjaOneID = '778'; RowKey = 'entra-dev-1' } }
                $null
            }
        }

        It 'sets requesterUid from the matched end user and keys consolidation per user' {
            Mock -CommandName Get-NinjaOneTicketUser -MockWith { [pscustomobject]@{ uid = 'user-uid'; email = 'jane@contoso.com' } }
            $null = New-NinjaOneTicket -Title 'MFA' -Description '<p>d</p>' -Client 9 -UserUPN 'jane@contoso.com' -DisplayName 'Jane'
            Should -Invoke -CommandName Get-NinjaOneTicketUser -Times 1 -ParameterFilter { $Emails -contains 'jane@contoso.com' -and $ClientId -eq 9 }
            Should -Invoke -CommandName Get-StringHash -Times 1 -ParameterFilter { $String -eq 'MFA|jane@contoso.com' }
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.requesterUid | Should -Be 'user-uid'
            $Body.description.htmlBody | Should -Be '<p>d</p>'
        }

        It 'notes an unmatched user in the description and sends no requester' {
            $null = New-NinjaOneTicket -Title 'MFA' -Description '<p>d</p>' -Client 9 -UserUPN 'jane@contoso.com' -DisplayName 'Jane'
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.PSObject.Properties.Name | Should -Not -Contain 'requesterUid'
            $Body.description.htmlBody | Should -Match 'Affected user: Jane \(jane@contoso.com\) - no matching NinjaOne end user'
            Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Warning' -and $message -like 'No NinjaOne end user*' }
        }

        It 'does not look the user up when the switch is off' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow }
                $null
            }
            $null = New-NinjaOneTicket -Title 'MFA' -Description 'd' -Client 9 -UserUPN 'jane@contoso.com'
            Should -Invoke -CommandName Get-NinjaOneTicketUser -Times 0
            Should -Invoke -CommandName Get-StringHash -Times 1 -ParameterFilter { $String -eq 'MFA' }
        }

        It 'attaches the device from the tenant sync map by Intune id' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 9 -TenantCustomerId 'tenant-guid' -AffectedDevice ([pscustomobject]@{ IntuneId = 'intune-1'; SerialNumber = 'SER123' })
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.nodeId | Should -Be 777
            $script:Calls | Where-Object { $_.Uri -like '*/devices-detailed*' } | Should -BeNullOrEmpty
        }

        It 'attaches the device from the tenant sync map by Entra device id' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 9 -TenantCustomerId 'tenant-guid' -AffectedDevice ([pscustomobject]@{ EntraDeviceId = 'entra-dev-1'; DisplayName = 'LAPTOP-01' })
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.nodeId | Should -Be 778
            Should -Invoke -CommandName Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $TableName -eq 'NinjaOneDeviceMap' -and $Filter -eq "PartitionKey eq 'tenant-guid' and RowKey eq 'entra-dev-1'" }
        }

        It 'falls back to the organisation devices by serial when the map has no row' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 9 -TenantCustomerId 'tenant-guid' -AffectedDevice ([pscustomobject]@{ IntuneId = 'unmapped'; SerialNumber = 'ser123' })
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.nodeId | Should -Be 501
            ($script:Calls | Where-Object { $_.Uri -like '*/devices-detailed*' }).Uri | Should -Be 'https://eu.ninjarmm.com/api/v2/devices-detailed?pageSize=1000&df=org = 9'
        }

        It 'warns and sends no nodeId when nothing matches the device' {
            $null = New-NinjaOneTicket -Title 't' -Description 'd' -Client 9 -AffectedDevice ([pscustomobject]@{ SerialNumber = 'NOPE'; DisplayName = 'PC-1' })
            $Body = (Get-CreateCall).Body | ConvertFrom-Json
            $Body.PSObject.Properties.Name | Should -Not -Contain 'nodeId'
            Should -Invoke -CommandName Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Warning' -and $message -like "No NinjaOne device matched 'PC-1'*" }
        }
    }

    Context 'consolidating onto an existing ticket' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($TableName -eq 'Extensionsconfig') { return New-ConfigRow -Extra @{ ConsolidateTickets = $true } }
                if ($Filter -like "*RowKey eq '9-hash'*") { return [pscustomobject]@{ PartitionKey = 'NinjaOne'; RowKey = '9-hash'; TicketID = 1380 } }
                $null
            }
        }

        It 'comments on the open ticket with a JSON multipart part and creates nothing' {
            $Result = New-NinjaOneTicket -Title 'Repeat' -Description '<p>again</p>' -Client 9
            $Result | Should -Be 'Comment added to NinjaOne ticket: 1380'
            $Comment = Get-CommentCall
            $Comment.Uri | Should -Be 'https://eu.ninjarmm.com/api/v2/ticketing/ticket/1380/comment'
            # Mock parameter binding unrolls the multipart container into its parts.
            $Part = @($Comment.Body)[0]
            $Part | Should -BeOfType [System.Net.Http.StringContent]
            $Part.Headers.ContentDisposition.Name | Should -Be 'comment'
            $Part.Headers.ContentType.MediaType | Should -Be 'application/json'
            $Json = $Part.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            $Json.public | Should -BeFalse
            $Json.htmlBody | Should -Be '<p>again</p>'
            Get-CreateCall | Should -BeNullOrEmpty
        }

        It 'raises a new ticket and records it when the existing one is closed' {
            Set-RestMock -StatusName 'Done' -ParentId 6000
            $Result = New-NinjaOneTicket -Title 'Repeat' -Description 'd' -Client 9
            $Result | Should -Be 'Ticket created in NinjaOne: 1382'
            Get-CommentCall | Should -BeNullOrEmpty
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
                $Entity.PartitionKey -eq 'NinjaOne' -and $Entity.RowKey -eq '9-hash' -and $Entity.TicketID -eq 1382
            }
        }

        It 'comments on a caller-supplied ticket without consulting the consolidation table' {
            $Result = New-NinjaOneTicket -Title 'Other' -Description 'd' -Client 9 -TicketId 555
            $Result | Should -Be 'Comment added to NinjaOne ticket: 555'
            Should -Invoke -CommandName Get-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $TableName -eq 'PSATickets' }
        }

        It 'falls back to a new ticket when the referenced ticket cannot be read' {
            Set-RestMock -TicketExists $false
            $Result = New-NinjaOneTicket -Title 'Repeat' -Description 'd' -Client 9
            $Result | Should -Be 'Ticket created in NinjaOne: 1382'
        }
    }
}
