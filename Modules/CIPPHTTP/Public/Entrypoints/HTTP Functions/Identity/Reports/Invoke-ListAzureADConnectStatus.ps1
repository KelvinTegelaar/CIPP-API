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
    # Optional. Which section to return: 'AzureADConnectSettings' for the sync status and
    # configuration, or 'AzureADObjectsInError' for objects that failed to sync. Omit to
    # return both.
    $DataToReturn = $Request.Query.DataToReturn

    switch ($DataToReturn) {
        'AzureADConnectSettings' { }
        'AzureADObjectsInError' { }
        default {
            if ($DataToReturn) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = 'DataToReturn must be AzureADConnectSettings or AzureADObjectsInError'
                    })
            }
        }
    }

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
        # A failed sub-request or later page would otherwise drop objects from the report without a word
        $FailedTypes = @(foreach ($Result in $Results) {
                if (($Result.status -as [int]) -lt 200 -or ($Result.status -as [int]) -gt 299) {
                    '{0}: {1}' -f $Result.id, ($Result.body.error.message ?? "HTTP $($Result.status)")
                } elseif ($Result.PagingIncomplete) {
                    '{0}: {1}' -f $Result.id, ($Result.PagingError ?? 'a continuation page failed')
                }
            })
        if ($FailedTypes.Count -gt 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = "Failed to read objects in error. $($FailedTypes -join '; ')"
                })
        }
        $ObjectsInError = @(
            foreach ($Result in $Results) {
                $Type = $Result.id -replace 's$' # Remove the 's' from the end of the type name
                foreach ($Object in $Result.body.value) {
                    # Graph returns every object; only those with provisioning errors belong in the report
                    if ($null -ne $Object.id -and $Object.onPremisesProvisioningErrors) {
                        $Object | Add-Member -NotePropertyName ObjectType -NotePropertyValue $Type -PassThru
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
