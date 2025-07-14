using namespace System.Net

Function Invoke-AddContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug
    Write-Host ($request | ConvertTo-Json -Depth 10 -Compress)

    try {
        $GUID = (New-Guid).GUID

        # Create a new ordered hashtable to store selected properties
        $contactObject = [ordered]@{}

        # Set name and comments first
        $contactObject["name"] = $Request.body.displayName
        $contactObject["comments"] = "Contact template created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

        # Copy specific properties we want to keep
        $propertiesToKeep = @(
            "displayName", "firstName", "lastName", "email", "hidefromGAL", "streetAddress", "postalCode",
            "city", "state", "country", "companyName", "mobilePhone", "businessPhone", "jobTitle", "website", "mailTip"
        )

        # Copy each property if it exists
        foreach ($prop in $propertiesToKeep) {
            if ($null -ne $Request.body.$prop) {
                $contactObject[$prop] = $Request.body.$prop
            }
        }

        # Convert to JSON
        $JSON = $contactObject | ConvertTo-Json -Depth 10

        # Save the template to Azure Table Storage
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'ContactTemplate'
        }

        Write-LogMessage -Headers $Headers -API $APINAME -message "Created Contact Template $($contactObject.name) with GUID $GUID" -Sev Info
        $body = [pscustomobject]@{'Results' = "Created Contact Template $($contactObject.name) with GUID $GUID" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APINAME -message "Failed to create Contact template: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to create Contact template: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
