using namespace System.Net

Function Invoke-AddExConnectorTemplate {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Write-Host ($request | ConvertTo-Json -Compress)

    try {
        $GUID = (New-Guid).GUID
        $Select = if ($Request.body.cippconnectortype -eq 'outbound') { 
            @( 
                'name', 'AllAcceptedDomains', 'CloudServicesMailEnabled', 'Comment', 'Confirm', 'ConnectorSource', 'ConnectorType', 'Enabled', 'IsTransportRuleScoped', 'RecipientDomains', 'RouteAllMessagesViaOnPremises', 'SenderRewritingEnabled', 'SmartHosts', 'TestMode', 'TlsDomain', 'TlsSettings', 'UseMXRecord'
            )
        }
        else {
            @(
                'name', 'SenderDomains', 'ConnectorSource', 'ConnectorType', 'EFSkipIPs', 'EFSkipLastIP', 'EFSkipMailGateway', 'EFTestMode', 'EFUsers', 'Enabled ', 'RequireTls', 'RestrictDomainsToCertificate', 'RestrictDomainsToIPAddresses', 'ScanAndDropRecipients', 'SenderIPAddresses', 'TlsSenderCertificateName', 'TreatMessagesAsInternal', 'TrustedOrganizations'
            )
        }

        $JSON = ([pscustomobject]$Request.body | Select-Object $Select) | ForEach-Object {
            $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
            $_ | Select-Object -Property $NonEmptyProperties 
        }
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.name } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$json"
            RowKey       = "$GUID"
            direction    = $request.body.cippconnectortype
            PartitionKey = 'ExConnectorTemplate'
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created Connector Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create Connector Template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Connector Template creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
