using namespace System.Net

function Invoke-AddBPATemplate {
    <#
    .SYNOPSIS
    Add a Best Practice Analyzer (BPA) template to CIPP storage
    
    .DESCRIPTION
    Creates and stores a Best Practice Analyzer (BPA) template in the CIPP templates table for future use in tenant analysis.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
        
    .NOTES
    Group: Tenant Management
    Summary: Add BPA Template
    Description: Creates and stores a Best Practice Analyzer (BPA) template in the CIPP templates table for future use in tenant analysis and best practice enforcement.
    Tags: Tenant Management,BPA,Templates,Best Practices
    Parameter: Request.body (object) [body] - BPA template object containing name and configuration
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: { "Results": "Successfully added template" } with HTTP 200 status
    Response: On error: { "Results": "BPA Template Creation failed: [error details]" } with HTTP 200 status
    Example: {
      "Results": "Successfully added template"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$($Request.body | ConvertTo-Json -Depth 10 -Compress)"
            RowKey       = $Request.body.name
            PartitionKey = 'BPATemplate'
            GUID         = $Request.body.name
        }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created BPA named $($Request.body.name)" -Sev 'Debug'

        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    }
    catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "BPA Template Creation failed: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "BPA Template Creation failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
