using namespace System.Net

function Invoke-ExecUserSettings {
    <#
    .SYNOPSIS
    Save user settings to CIPP storage
    
    .DESCRIPTION
    Saves user settings and preferences to Azure Table Storage for persistence across sessions, excluding system properties.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
        
    .NOTES
    Group: User Management
    Summary: Exec User Settings
    Description: Saves user settings and preferences to Azure Table Storage, excluding system properties like CurrentTenant, pageSizes, sidebarShow, sidebarUnfoldable, and _persist.
    Tags: User Management,Settings,Storage
    Parameter: currentSettings (object) [body] - User's current settings object to save
    Parameter: user (string) [body] - User identifier for storing settings
    Response: Returns a response object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: "Successfully added user settings" with HTTP 200 status
    Response: On error: Error message with HTTP 400 status
    Example: {
      "Results": "Successfully added user settings"
    }
    Error: Returns error details if the operation fails to save user settings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $object = $Request.Body.currentSettings | Select-Object * -ExcludeProperty CurrentTenant, pageSizes, sidebarShow, sidebarUnfoldable, _persist | ConvertTo-Json -Compress -Depth 10
        $User = $Request.Body.user
        $Table = Get-CippTable -tablename 'UserSettings'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$object"
            RowKey       = "$User"
            PartitionKey = 'UserSettings'
        }
        $StatusCode = [HttpStatusCode]::OK
        $Results = [pscustomobject]@{'Results' = 'Successfully added user settings' }
    }
    catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })

}
