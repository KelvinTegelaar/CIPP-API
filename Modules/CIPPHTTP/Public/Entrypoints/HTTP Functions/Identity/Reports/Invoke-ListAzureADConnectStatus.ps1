Function Invoke-ListAzureADConnectStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Retrieves Entra ID Connect (Azure AD Connect) synchronization status and configuration for a tenant, including sync intervals, password sync, and pass-through authentication settings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.TenantFilter
    $DataToReturn = $Request.Query.DataToReturn
    Write-Host "DataToReturn: $DataToReturn"

    if (($DataToReturn -eq 'AzureADConnectSettings') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
        $ADConnectStatusGraph = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        $LastSyncDateTime = $ADConnectStatusGraph.onPremisesLastSyncDateTime
        # The field name promises hours since the last on-prem sync, but it was returning the raw
        # timestamp. Compute the actual elapsed hours ($null when the tenant has never synced); the
        # timestamp itself is still available under lastSyncDateTime and raw.
        $HoursFromLastSync = if ($LastSyncDateTime) {
            [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]$LastSyncDateTime).ToUniversalTime()).TotalHours, 2)
        } else {
            $null
        }
        $AzureADConnectSettings = [PSCustomObject]@{
            dirSyncEnabled            = [boolean]$ADConnectStatusGraph.onPremisesSyncEnabled
            numberOfHoursFromLastSync = $HoursFromLastSync
            lastSyncDateTime          = $LastSyncDateTime
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
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $AzureADConnectSettings
            })
    } elseif ($DataToReturn -eq 'AzureADObjectsInError') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($ObjectsInError)
            })
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($FinalObject)
            })
    }
}
