using namespace System.Net

function Invoke-ListAzureADConnectStatus {
    <#
    .SYNOPSIS
    List Azure AD Connect status and objects in error for a tenant
    
    .DESCRIPTION
    Retrieves Azure AD Connect synchronization status and objects in error for a specified tenant, supporting selection of data to return (settings or objects in error).
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    
    .NOTES
    Group: Directory Reports
    Summary: List Azure AD Connect Status
    Description: Retrieves Azure AD Connect synchronization status and objects in error for a specified tenant, supporting selection of data to return (settings or objects in error).
    Tags: Directory,Azure AD Connect,Sync,Status,Errors
    Parameter: TenantFilter (string) [query] - Target tenant identifier
    Parameter: DataToReturn (string) [query] - Data to return: 'AzureADConnectSettings', 'AzureADObjectsInError', or both
    Response: Returns a response object with the following properties:
    Response: - AzureADConnectSettings (object): Directory sync status and last sync time
    Response: - ObjectsInError (array): Array of objects in error with type, displayName, and error details
    Example: {
      "AzureADConnectSettings": {
        "dirSyncEnabled": true,
        "numberOfHoursFromLastSync": "2024-01-15T10:30:00Z",
        "raw": { ... }
      },
      "ObjectsInError": [
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "displayName": "John Doe",
          "ObjectType": "User",
          "onPremisesProvisioningErrors": [ ... ]
        }
      ]
    }
    Error: Returns error details if the operation fails to retrieve status or objects in error.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.TenantFilter
    $DataToReturn = $Request.Query.DataToReturn
    Write-Host "DataToReturn: $DataToReturn"

    if (($DataToReturn -eq 'AzureADConnectSettings') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
        $ADConnectStatusGraph = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        $AzureADConnectSettings = [PSCustomObject]@{
            dirSyncEnabled            = [boolean]$ADConnectStatusGraph.onPremisesSyncEnabled
            numberOfHoursFromLastSync = $ADConnectStatusGraph.onPremisesLastSyncDateTime
            raw                       = $ADConnectStatusGraph
        }
    }

    if (($DataToReturn -eq 'AzureADObjectsInError') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
        $SelectList = 'id,displayName,onPremisesProvisioningErrors,createdDateTime'
        $Types = 'Users', 'Contacts', 'Groups'

        $GraphRequest = @(
            foreach ($Type in $Types) {
                @{
                    id     = $Type.ToLower()
                    method = 'GET'
                    url    = "/$Type`?`$select=$SelectList"
                }
            }
        )

        $Results = New-GraphBulkRequest -Requests $GraphRequest -tenantid $TenantFilter -verbose
        $ObjectsInError = @(
            foreach ($Result in $Results) {
                $Type = $Result.id -replace 's$' # Remove the 's' from the end of the type name
                $Result.body.value | ForEach-Object {
                    if ($null -ne $_.id) {
                        $_ | Add-Member -NotePropertyName ObjectType -NotePropertyValue $Type -PassThru
                    }
                }
            }
        )
    }

    if ([string]::IsNullOrEmpty($DataToReturn)) {
        $FinalObject = [PSCustomObject]@{
            AzureADConnectSettings = $AzureADConnectSettings
            ObjectsInError         = $ObjectsInError
        }
    }
    if ($DataToReturn -eq 'AzureADConnectSettings') {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $AzureADConnectSettings
            })
    }
    elseif ($DataToReturn -eq 'AzureADObjectsInError') {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($ObjectsInError)
            })
    }
    else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($FinalObject)
            })
    }
}
