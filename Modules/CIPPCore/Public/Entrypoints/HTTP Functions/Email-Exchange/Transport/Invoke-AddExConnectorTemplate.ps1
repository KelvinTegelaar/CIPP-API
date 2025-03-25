using namespace System.Net

Function Invoke-AddExConnectorTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    Write-Host ($Request | ConvertTo-Json -Compress)

    try {
        $GUID = (New-Guid).GUID
        $Select = if ($Request.Body.cippconnectortype -eq 'outbound') {
            @(
                'name', 'AllAcceptedDomains', 'CloudServicesMailEnabled', 'Comment', 'Confirm', 'ConnectorSource', 'ConnectorType', 'Enabled', 'IsTransportRuleScoped', 'RecipientDomains', 'RouteAllMessagesViaOnPremises', 'SenderRewritingEnabled', 'SmartHosts', 'TestMode', 'TlsDomain', 'TlsSettings', 'UseMXRecord'
            )
        } else {
            @(
                'name', 'SenderDomains', 'ConnectorSource', 'ConnectorType', 'EFSkipIPs', 'EFSkipLastIP', 'EFSkipMailGateway', 'EFTestMode', 'EFUsers', 'Enabled ', 'RequireTls', 'RestrictDomainsToCertificate', 'RestrictDomainsToIPAddresses', 'ScanAndDropRecipients', 'SenderIPAddresses', 'TlsSenderCertificateName', 'TreatMessagesAsInternal', 'TrustedOrganizations'
            )
        }

        $JSON = ([pscustomobject]$Request.Body | Select-Object $Select) | ForEach-Object {
            $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties
        }
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.name } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            direction    = $Request.Body.cippconnectortype
            PartitionKey = 'ExConnectorTemplate'
        }
        $Result = "Successfully created Connector Template: $($Request.Body.name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Connector Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
