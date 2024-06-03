using namespace System.Net

Function Invoke-ListAzureADConnectStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $DataToReturn = $Request.Query.DataToReturn

    if (($DataToReturn -eq 'AzureADConnectSettings') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
        $ADConnectStatusGraph = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        #$ADConnectStatusGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -Uri "https://main.iam.ad.ext.azure.com/api/Directories/ADConnectStatus" -Method "GET"
        #$PasswordSyncStatusGraph = New-ClassicAPIGetRequest -Resource "74658136-14ec-4630-ad9b-26e160ff0fc6" -TenantID $TenantFilter -Uri "https://main.iam.ad.ext.azure.com/api/Directories/GetPasswordSyncStatus" -Method "GET"
        $AzureADConnectSettings = [PSCustomObject]@{
            dirSyncEnabled            = [boolean]$ADConnectStatusGraph.onPremisesSyncEnabled
            #dirSyncConfigured                = [boolean]$ADConnectStatusGraph.dirSyncConfigured
            #passThroughAuthenticationEnabled = [boolean]$ADConnectStatusGraph.passThroughAuthenticationEnabled
            #seamlessSingleSignOnEnabled      = [boolean]$ADConnectStatusGraph.seamlessSingleSignOnEnabled
            numberOfHoursFromLastSync = $ADConnectStatusGraph.onPremisesLastSyncDateTime
            #passwordSyncStatus               = [boolean]$PasswordSyncStatusGraph
            raw                       = $ADConnectStatusGraph
        }
    }

    if (($DataToReturn -eq 'AzureADObjectsInError') -or ([string]::IsNullOrEmpty($DataToReturn)) ) {
        $selectlist = 'id', 'displayName', 'onPremisesProvisioningErrors', 'createdDateTime'
        $Types = 'Users', 'Contacts', 'Groups'

        $GraphRequest = foreach ($Type in $types) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($Type)?`$select=$($selectlist -join ',')" -tenantid $TenantFilter | ForEach-Object {
                if ($_.id -ne $null) {
                    $_ | Add-Member -NotePropertyName ObjectType -NotePropertyValue $Type
                    $_
                }

            }
        }
        $ObjectsInError = @($GraphRequest)
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
    } elseif ($DataToReturn -eq 'AzureADObjectsInError') {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($ObjectsInError)
            })
    } else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($FinalObject)
            })
    }


}
